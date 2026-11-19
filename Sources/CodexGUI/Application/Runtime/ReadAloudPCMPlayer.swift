import AVFoundation
import Accelerate
import Foundation

/// Decodes interleaved signed PCM16 LE, the raw audio/pcm representation.
/// App-server V3 supplies no encoding discriminator; this adapter assumes its default output
/// uses that representation. Controlled fixtures verify the decoder, not live V3 negotiation.
/// Rate and channel metadata come from each packet rather than a container header.
struct ReadAloudAudioChunk: Sendable
{
	static let maximumPacketBytes = 1024 * 1024
	let pcmData: Data
	let sampleRate: Int
	let channelCount: Int
	let frameCount: Int

	init(
		base64Data: String,
		sampleRate: Int,
		numChannels: Int,
		samplesPerChannel: Int? = nil
	) throws
	{
		let maximumEncodedBytes = ((Self.maximumPacketBytes + 2) / 3) * 4
		guard base64Data.utf8.count <= maximumEncodedBytes
		else
		{
			throw ReadAloudPCMError.packetTooLarge
		}
		guard let data = Data(base64Encoded: base64Data)
		else
		{
			throw ReadAloudPCMError.invalidEncoding
		}
		try self.init(
			pcmData: data,
			sampleRate: sampleRate,
			numChannels: numChannels,
			samplesPerChannel: samplesPerChannel
		)
	}

	init(
		pcmData: Data,
		sampleRate: Int,
		numChannels: Int,
		samplesPerChannel: Int? = nil
	) throws
	{
		guard (8000 ... 192000).contains(sampleRate), (1 ... 8).contains(numChannels)
		else
		{
			throw ReadAloudPCMError.invalidFormat
		}
		guard !pcmData.isEmpty
		else
		{
			throw ReadAloudPCMError.emptyAudio
		}
		guard pcmData.count <= Self.maximumPacketBytes
		else
		{
			throw ReadAloudPCMError.packetTooLarge
		}
		let bytesPerFrame = 2 * numChannels
		guard pcmData.count.isMultiple(of: bytesPerFrame)
		else
		{
			throw ReadAloudPCMError.sampleCountMismatch
		}
		let frameCount = pcmData.count / bytesPerFrame
		guard samplesPerChannel == nil || samplesPerChannel == frameCount
		else
		{
			throw ReadAloudPCMError.sampleCountMismatch
		}
		self.pcmData = pcmData
		self.sampleRate = sampleRate
		channelCount = numChannels
		self.frameCount = frameCount
	}

	/// Conversion is explicit so host alignment and native byte order cannot reinterpret samples.
	func normalizedInterleavedSamples() -> [Float]
	{
		pcmData.withUnsafeBytes
		{
			bytes in
			let samples = bytes.bindMemory(to: UInt8.self)
			return stride(
				from: 0,
				to: samples.count,
				by: 2
			).map
			{
				index in
				let bits = UInt16(samples[index]) | (UInt16(samples[index + 1]) << 8)
				return Float(Int16(bitPattern: bits)) / 32768
			}
		}
	}
}

enum ReadAloudPCMError: Error, Equatable
{
	case invalidEncoding, invalidFormat, emptyAudio, packetTooLarge
	case sampleCountMismatch, queueFull, segmentNotDrained, formatChanged, playbackUnavailable
}

/// Counts actual scheduled float-buffer bytes and rejects callbacks from retired playback.
struct ReadAloudPlaybackQueue
{
	struct Ticket: Hashable, Sendable
	{
		let generation: UInt64
		let sequence: UInt64
	}

	private let maximumBytes: Int
	private var generation: UInt64 = 0
	private var sequence: UInt64 = 0
	private var buffers: [UInt64: Int] = [:]
	private(set) var queuedBytes = 0
	private var finishing = false
	private var reportedDrain = false

	init(maximumBytes: Int = 8 * 1024 * 1024)
	{
		self.maximumBytes = max(
			0,
			maximumBytes
		)
	}

	mutating func enqueue(byteCount: Int) throws -> Ticket
	{
		if finishing
		{
			guard reportedDrain, buffers.isEmpty
			else
			{
				throw ReadAloudPCMError.segmentNotDrained
			}
			finishing = false
			reportedDrain = false
		}
		guard byteCount > 0, byteCount <= maximumBytes - queuedBytes
		else
		{
			throw ReadAloudPCMError.queueFull
		}
		sequence &+= 1
		buffers[sequence] = byteCount
		queuedBytes += byteCount
		return Ticket(
			generation: generation,
			sequence: sequence
		)
	}

	mutating func complete(_ ticket: Ticket) -> Bool
	{
		guard ticket.generation == generation,
				let byteCount = buffers.removeValue(forKey: ticket.sequence)
		else
		{
			return false
		}
		queuedBytes -= byteCount
		return reportDrainIfReady()
	}

	mutating func finish() -> Bool
	{
		finishing = true
		return reportDrainIfReady()
	}

	mutating func reset()
	{
		generation &+= 1
		buffers.removeAll()
		queuedBytes = 0
		finishing = false
		reportedDrain = false
	}

	private mutating func reportDrainIfReady() -> Bool
	{
		guard finishing, buffers.isEmpty, !reportedDrain
		else
		{
			return false
		}
		reportedDrain = true
		return true
	}
}

@MainActor
protocol ReadAloudAudioPlaying: AnyObject
{
	var onDrained: (() -> Void)?
	{
		get set
	}
	func enqueue(_ chunk: ReadAloudAudioChunk) throws
	func finish()
	func stop()
}

/// Native playback completes at the device-facing callback, after scheduled samples play.
@MainActor
final class ReadAloudPCMPlayer: ReadAloudAudioPlaying
{
	var onDrained: (() -> Void)?
	var onPlaybackLevel: ((Double) -> Void)?
	private var playbackMeter: UUID?
	private var engine: AVAudioEngine?
	private weak var duplexEngine: AVAudioEngine?
	private var player: AVAudioPlayerNode?
	private var format: AVAudioFormat?
	private var queue = ReadAloudPlaybackQueue()

	func useDuplexEngine(_ engine: AVAudioEngine?)
	{
		stop()
		duplexEngine = engine
	}

	func enqueue(_ chunk: ReadAloudAudioChunk) throws
	{
		if let format,
			format.sampleRate != Double(chunk.sampleRate)
			|| format.channelCount != AVAudioChannelCount(chunk.channelCount)
		{
			throw ReadAloudPCMError.formatChanged
		}
		let ticket = try queue.enqueue(
			byteCount: chunk.frameCount * chunk.channelCount * MemoryLayout<Float>.size
		)
		do
		{
			let format = try prepareEngine(for: chunk)
			guard let buffer = AVAudioPCMBuffer(
				pcmFormat: format,
				frameCapacity: AVAudioFrameCount(chunk.frameCount)
			), let channels = buffer.floatChannelData, let player
			else
			{
				throw ReadAloudPCMError.playbackUnavailable
			}
			buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
			let samples = chunk.normalizedInterleavedSamples()
			for channel in 0 ..< chunk.channelCount
			{
				for frame in 0 ..< chunk.frameCount
				{
					channels[channel][frame] = samples[frame * chunk.channelCount + channel]
				}
			}
			player.scheduleBuffer(
				buffer,
				completionCallbackType: .dataPlayedBack
			)
			{
				[weak self] _ in
				Task
				{
					@MainActor [weak self] in self?.didPlay(ticket)
				}
			}
		}
		catch
		{
			stop()
			throw error
		}
	}

	func finish()
	{
		if queue.finish()
		{
			onDrained?()
		}
	}

	/// Drops scheduled speech while keeping the duplex graph and its input tap running.
	func discardQueuedAudio()
	{
		queue.reset()
		player?.stop()
		if engine?.isRunning == true
		{
			player?.play()
		}
	}

	func stop()
	{
		queue.reset()
		player?.stop()
		if let player
		{
			if playbackMeter != nil
			{
				player.removeTap(onBus: 0)
			}
			engine?.detach(player)
		}
		playbackMeter = nil
		if duplexEngine == nil
		{
			engine?.stop()
			engine?.reset()
		}
		player = nil
		engine = nil
		format = nil
	}

	private func prepareEngine(for chunk: ReadAloudAudioChunk) throws -> AVAudioFormat
	{
		if let format
		{
			return format
		}
		guard let format = AVAudioFormat(
			standardFormatWithSampleRate: Double(chunk.sampleRate),
			channels: AVAudioChannelCount(chunk.channelCount)
		)
		else
		{
			throw ReadAloudPCMError.invalidFormat
		}
		let engine = duplexEngine ?? AVAudioEngine()
		let player = AVAudioPlayerNode()
		engine.attach(player)
		engine.connect(
			player,
			to: engine.mainMixerNode,
			format: format
		)
		self.engine = engine
		self.player = player
		if onPlaybackLevel != nil
		{
			installPlaybackMeter(on: player)
		}
		if !engine.isRunning
		{
			engine.prepare()
			try engine.start()
		}
		player.play()
		self.format = format
		return format
	}

	private func installPlaybackMeter(on player: AVAudioPlayerNode)
	{
		let meter = UUID()
		playbackMeter = meter
		player.installTap(
			onBus: 0,
			bufferSize: 2048,
			format: nil
		)
		{
			[weak self] buffer, _ in
			guard let channels = buffer.floatChannelData, buffer.frameLength > 0
			else
			{
				return
			}
			var rms: Float = 0
			for channel in 0 ..< Int(buffer.format.channelCount)
			{
				var channelRMS: Float = 0
				vDSP_rmsqv(
					channels[channel],
					1,
					&channelRMS,
					vDSP_Length(buffer.frameLength)
				)
				rms = max(
					rms,
					channelRMS
				)
			}
			let level = Double(rms)
			Task
			{
				@MainActor [weak self] in
				guard let self, self.playbackMeter == meter, self.queue.queuedBytes > 0
				else
				{
					return
				}
				self.onPlaybackLevel?(level)
			}
		}
	}

	private func didPlay(_ ticket: ReadAloudPlaybackQueue.Ticket)
	{
		let hadAudio = queue.queuedBytes > 0
		if queue.complete(ticket)
		{
			onDrained?()
		}
		if hadAudio, queue.queuedBytes == 0
		{
			onPlaybackLevel?(0)
		}
	}
}
