import Foundation

/// Owns a private ephemeral realtime thread and its local audio device lifetime.
@MainActor
final class ReadAloudRuntime
{
	@MainActor
	private final class Session
	{
		let inbox = ReadAloudEventInbox()
		let player: any ReadAloudAudioPlaying
		var threadID: String?
		var cancelled = false
		init(player: any ReadAloudAudioPlaying)
		{
			self.player = player
		}
		func cancel()
		{
			cancelled = true
			player.stop()
			inbox.fail(CancellationError())
		}
		func checkCancellation() throws
		{
			try Task.checkCancellation()
			if cancelled
			{
				throw CancellationError()
			}
		}

	}
	private let service: any ReadAloudService
	private let makePlayer: () -> any ReadAloudAudioPlaying
	private var session: Session?

	init(
		service: any ReadAloudService,
		makePlayer: @escaping () -> any ReadAloudAudioPlaying =
		{
			ReadAloudPCMPlayer()
		}
	)
	{
		self.service = service
		self.makePlayer = makePlayer
	}

	func cancel()
	{
		session?.cancel()
	}

	func play(
		_ request: ReadAloudRequest,
		onStarted: @escaping () -> Void
	) async throws
	{
		cancel()
		guard let path = request.context.workspace.canonicalCheckoutPath
		else
		{
			throw ReadAloudError.unavailable
		}
		let parts = try ReadAloudTextSegments.make(request.text)
		let current = Session(player: makePlayer())
		session = current
		current.player.onDrained =
		{
			[weak current] in current?.inbox.push(.playbackDrained)
		}
		service.onReadAloudEvent =
		{
			[weak current] threadID, event in
			guard let current, current.threadID == threadID
			else
			{
				return
			}
			current.inbox.push(event)
		}
		var failure: Error?
		do
		{
			try await withTaskCancellationHandler
			{
				try current.checkCancellation()
				// Keep receipt capture alive after local cancellation, so a created private
				// thread can be retired rather than losing its identity with a cancelled RPC.
				let service = self.service
				let threadID = try await Task
				{
					@MainActor in
					try await service.createReadAloudThread(in: URL(fileURLWithPath: path))
				}.value
				current.threadID = threadID
				try current.checkCancellation()
				try await Task
				{
					@MainActor in
					try await service.startReadAloudSession(threadID: threadID)
				}.value
				try current.checkCancellation()
				let ready = try await current.inbox.next()
				guard case .started(version: "v3") = ready
				else
				{
					throw failureForUnexpected(ready)
				}
				onStarted()
				for part in parts
				{
					try current.checkCancellation()
					try await Task
					{
						@MainActor in try await service.appendReadAloudSpeech(
							threadID: threadID,
							text: part
						)
					}.value
					try current.checkCancellation()
					var backendFinished = false
					var hasAudio = false
					var drained = false
					while !drained
					{
						let event = try await current.inbox.next()
						switch event
						{
						case .audio(let chunk):
							guard !backendFinished
							else
							{
								throw ReadAloudError.invalidResponse
							}
							hasAudio = true
							try current.player.enqueue(chunk)
						case .segmentFinished:
							guard !backendFinished
							else
							{
								throw ReadAloudError.invalidResponse
							}
							backendFinished = true
							// In V3 transcript/done is the forwarded assistant turn.done boundary.
							// Device drain is separately required before sending another segment.
							if hasAudio
							{
								current.player.finish()
							}
							else
							{
								drained = true
							}
						case .playbackDrained:
							guard backendFinished
							else
							{
								throw ReadAloudError.invalidResponse
							}
							drained = true
						default: throw failureForUnexpected(event)
						}
					}
				}
			} onCancel:
			{
				Task
				{
					@MainActor in current.cancel()
				}
			}
		}
		catch
		{
			failure = error
		}
		current.cancel()
		if session === current
		{
			session = nil; service.onReadAloudEvent = nil
		}
		if let threadID = current.threadID
		{
			// Cleanup must run even though the operation task itself may be cancelled.
			let service = self.service
			await Task
			{
				@MainActor in await service.retireReadAloudThread(threadID: threadID)
			}
			.value
		}
		if let failure
		{
			throw failure
		}
	}

	private func failureForUnexpected(_ event: ReadAloudBackendEvent) -> Error
	{
		switch event
		{
		case .failed(let message): return ReadAloudError.backend(message)
		case .closed: return ReadAloudError.sessionClosed
		default: return ReadAloudError.invalidResponse
		}
	}
}

/// A bounded actor-owned inbox pairs notifications with waits, without silence heuristics.
@MainActor
private final class ReadAloudEventInbox
{
	private var queue: [ReadAloudBackendEvent] = []
	private var queuedAudioBytes = 0
	private var waiter: CheckedContinuation<ReadAloudBackendEvent, Error>?
	private var deadline: Task<Void, Never>?
	private var failure: Error?

	func push(_ event: ReadAloudBackendEvent)
	{
		guard failure == nil
		else
		{
			return
		}
		if let waiter
		{
			self.waiter = nil
			deadline?.cancel(); deadline = nil
			waiter.resume(returning: event)
			return
		}
		let bytes: Int
		if case .audio(let chunk) = event
		{
			bytes = chunk.pcmData.count
		}
		else
		{
			bytes = 0
		}
		guard queue.count < 128,
				queuedAudioBytes + bytes <= 8 * 1024 * 1024
		else
		{
			fail(ReadAloudError.eventOverflow); return
		}
		queuedAudioBytes += bytes
		queue.append(event)
	}

	func next() async throws -> ReadAloudBackendEvent
	{
		try Task.checkCancellation()
		if let failure
		{
			throw failure
		}
		if !queue.isEmpty
		{
			let event = queue.removeFirst()
			if case .audio(let chunk) = event
			{
				queuedAudioBytes -= chunk.pcmData.count
			}
			return event
		}
		return try await withCheckedThrowingContinuation
		{
			continuation in
			waiter = continuation
			deadline = Task
			{
				[weak self] in
				do
				{
					try await Task.sleep(for: .seconds(60)); self?.fail(ReadAloudError.timedOut)
				}
				catch
				{
				}
			}
		}
	}

	func fail(_ error: Error)
	{
		guard failure == nil
		else
		{
			return
		}
		failure = error
		deadline?.cancel(); deadline = nil
		queue.removeAll(); queuedAudioBytes = 0
		let waiter = self.waiter
		self.waiter = nil
		waiter?.resume(throwing: error)
	}
}
