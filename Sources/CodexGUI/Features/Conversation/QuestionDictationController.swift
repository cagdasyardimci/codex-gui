import AppKit
import AVFoundation
import Speech

/// Owns the microphone and speech recognition session for one question card.
@MainActor
final class QuestionDictationController
{
	private let engine = AVAudioEngine()
	private var request: SFSpeechAudioBufferRecognitionRequest?
	private var task: SFSpeechRecognitionTask?
	private var generation = UUID()
	private var tapInstalled = false
	private var onUpdate: ((String) -> Void)?
	private var latestText = ""
	private var completionTimeout: Task<Void, Never>?
	private(set) var isRecording = false
	var onRecordingChanged: ((Bool) -> Void)?
	var onLevelChanged: ((Float) -> Void)?
	var onFinished: ((String) -> Void)?

	func start(onUpdate: @escaping (String) -> Void)
	{
		cancel()
		self.onUpdate = onUpdate
		latestText = ""
		let session = UUID()
		generation = session
		Task
		{
			@MainActor [weak self] in
			let speechStatus = await Self.speechAuthorization()
			guard speechStatus == .authorized, self?.generation == session
			else
			{
				return
			}
			let granted = await AVCaptureDevice.requestAccess(for: .audio)
			guard let self, self.generation == session, speechStatus == .authorized,
					granted
			else
			{
				return
			}
			self.beginRecognition(session: session)
		}
	}

	private nonisolated static func speechAuthorization() async
		-> SFSpeechRecognizerAuthorizationStatus
	{
		await withCheckedContinuation
		{
			continuation in
			SFSpeechRecognizer.requestAuthorization
			{
				status in
				continuation.resume(returning: status)
			}
		}
	}

	private func beginRecognition(session: UUID)
	{
		guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable
		else
		{
			return
		}
		let request = SFSpeechAudioBufferRecognitionRequest()
		request.shouldReportPartialResults = true
		self.request = request
		let input = engine.inputNode
		let format = input.outputFormat(forBus: 0)
		guard format.sampleRate > 0, format.channelCount > 0
		else
		{
			self.request = nil; return
		}
		input.installTap(
			onBus: 0,
			bufferSize: 1024,
			format: format
		)
		{
			@Sendable [weak self] buffer, _ in
			request.append(buffer)
			let level = Self.level(in: buffer)
			Task
			{
				@MainActor [weak self] in
				guard let self, self.generation == session, self.isRecording
				else
				{
					return
				}
				self.onLevelChanged?(level)
			}
		}
		tapInstalled = true
		task = recognizer.recognitionTask(with: request)
		{
			@Sendable [weak self] result, error in
			let text = result?.bestTranscription.formattedString
			let finished = result?.isFinal == true || error != nil
			Task
			{
				@MainActor [weak self] in
				guard let self, self.generation == session
				else
				{
					return
				}
				if let text
				{
					self.latestText = text; self.onUpdate?(text)
				}
				if finished
				{
					self.complete()
				}
			}
		}
		do
		{
			engine.prepare()
			try engine.start()
			isRecording = true
			onRecordingChanged?(true)
		}
		catch
		{
			finish()
		}
	}

	func stop()
	{
		guard isRecording
		else
		{
			return
		}
		engine.stop()
		engine.inputNode.removeTap(onBus: 0)
		tapInstalled = false
		request?.endAudio()
		isRecording = false
		onRecordingChanged?(false)
		let session = generation
		completionTimeout = Task
		{
			@MainActor [weak self] in
			try? await Task.sleep(for: .seconds(3))
			guard !Task.isCancelled, let self, self.generation == session
			else
			{
				return
			}
			self.complete()
		}
	}

	private nonisolated static func level(in buffer: AVAudioPCMBuffer) -> Float
	{
		guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0
		else
		{
			return 0
		}
		var energy: Float = 0
		for index in 0 ..< Int(buffer.frameLength)
		{
			energy += samples[index] * samples[index]
		}
		let rms = sqrt(energy / Float(buffer.frameLength))
		let decibels = 20 * log10(max(
			rms,
			0.000001
		))
		return min(
			1,
			max(
				0,
				(decibels + 60) / 48
			)
		)
	}

	private func complete()
	{
		let text = latestText
		finish()
		onFinished?(text)
	}

	func cancel()
	{
		generation = UUID()
		finish()
	}

	private func finish()
	{
		generation = UUID()
		completionTimeout?.cancel()
		completionTimeout = nil
		if engine.isRunning
		{
			engine.stop()
		}
		if tapInstalled
		{
			engine.inputNode.removeTap(onBus: 0); tapInstalled = false
		}
		request?.endAudio()
		request = nil
		task?.cancel()
		task = nil
		onUpdate = nil
		if isRecording
		{
			isRecording = false
			onRecordingChanged?(false)
		}
	}
}
