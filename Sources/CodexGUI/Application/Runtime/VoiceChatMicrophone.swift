import AVFoundation
import os

/// The tap and converter run off the main actor. Only bounded PCM packets cross to the session.
@MainActor
final class VoiceChatMicrophone
{
	nonisolated static let sampleRate = 24_000

	private(set) var engine: AVAudioEngine?
	private var tapInstalled = false

	static func requestPermission() async -> Bool
	{
		await AVCaptureDevice.requestAccess(for: .audio)
	}

	func start(output: AsyncStream<Data>.Continuation) throws
	{
		stopCapture()
		let engine: AVAudioEngine
		if let runningEngine = self.engine
		{
			engine = runningEngine
		}
		else
		{
			let duplex = AVAudioEngine()
			// Referencing playback and input from the same graph enables system echo cancellation.
			try? duplex.inputNode.setVoiceProcessingEnabled(true)
			engine = duplex
			self.engine = engine
		}
		let node = engine.inputNode
		let input = node.outputFormat(forBus: 0)
		guard input.sampleRate > 0, input.channelCount > 0,
				let pcm = AVAudioFormat(
				commonFormat: .pcmFormatInt16,
				sampleRate: Double(Self.sampleRate),
				channels: 1,
				interleaved: true
				),
				let converter = AVAudioConverter(
				from: input,
				to: pcm
				)
		else
		{
			throw ReadAloudPCMError.invalidFormat
		}

		Self.installTap(
			on: node,
			input: input,
			pcm: pcm,
			converter: converter,
			output: output
		)
		tapInstalled = true
		do
		{
			if !engine.isRunning
			{
				try engine.start()
			}
		}
		catch
		{
			stop()
			throw error
		}
	}

	/// The audio engine invokes the tap on its render thread.
	private nonisolated static func installTap(
		on node: AVAudioInputNode,
		input: AVAudioFormat,
		pcm: AVAudioFormat,
		converter: AVAudioConverter,
		output: AsyncStream<Data>.Continuation
	)
	{
		node.installTap(
			onBus: 0,
			bufferSize: 1024,
			format: input
		)
		{
			buffer, _ in
			let frameCapacity = AVAudioFrameCount(
				ceil(Double(buffer.frameLength) * pcm.sampleRate / input.sampleRate)
			) + 32
			guard let converted = AVAudioPCMBuffer(
				pcmFormat: pcm,
				frameCapacity: frameCapacity
			)
			else
			{
				return
			}
			// AVAudioConverter pulls this packet synchronously while the audio tap owns it.
			let packet = OSAllocatedUnfairLock(uncheckedState: Optional(buffer))
			let status = converter.convert(
				to: converted,
				error: nil
			)
			{
				_, status in
				packet.withLockUnchecked
				{
					buffer in
					let samples = buffer
					buffer = nil
					status.pointee = samples == nil ? .noDataNow : .haveData
					return samples
				}
			}
			if status != .error, converted.frameLength > 0,
				let samples = converted.int16ChannelData?.pointee
			{
				_ = output.yield(Data(
					bytes: samples,
					count: Int(converted.frameLength) * MemoryLayout<Int16>.size
				))
			}
		}
	}

	func stopCapture()
	{
		if tapInstalled
		{
			engine?.inputNode.removeTap(onBus: 0)
			tapInstalled = false
		}
	}

	func stop()
	{
		stopCapture()
		engine?.stop()
		engine = nil
	}
}
