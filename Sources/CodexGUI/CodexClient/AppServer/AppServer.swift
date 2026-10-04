import Foundation

/// Owns the child process and newline-delimited JSON transport. All mutable state stays on the main
/// actor.
@MainActor
final class AppServer: CodexService
{
	let executableOverride: URL?
	private let requestTimeout: Duration
	let versionCheckTimeout: DispatchTimeInterval
	private var process: Process?
	private var input: FileHandle?
	private var messageWriter: ProtocolMessageWriter?
	private var output: FileHandle?
	private var errorOutput: FileHandle?
	private var stderrReader: StderrReader?
	private var diagnosticsFinalizing = Set<UUID>()
	private var frameContinuation: AsyncStream<Data>.Continuation?
	private var messageTask: Task<Void, Never>?
	private var nextID = 1
	private var pending: [Int: CheckedContinuation<ProtocolJSONPayload, Error>] = [:]
	private var requestWrites: [Int: ProtocolWriteTicket] = [:]
	private var requestTimeouts: [Int: Task<Void, Never>] = [:]
	var interactions:
		[String: (
			id: JSONRPCRequestID,
			threadId: String,
			kind: InteractionKind,
			decisions: [ApprovalDecision]?,
			permissions: [String: Any]?
		)] = [:]
	var answeredInteractions = Set<String>()
	private(set) var connectionGeneration = UUID()
	private let diagnostics = BackendDiagnosticsBuffer()
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	var backendDiagnostics: BackendDiagnosticsSnapshot
	{
		diagnostics.snapshot()
	}

	init(
		executableOverride: URL? = nil,
		requestTimeout: Duration = .seconds(45),
		versionCheckTimeout: DispatchTimeInterval = .seconds(10)
	)
	{
		self.executableOverride = executableOverride
		self.requestTimeout = requestTimeout
		self.versionCheckTimeout = versionCheckTimeout
	}

	func connect() async throws
	{
		disconnect()
		let generation = connectionGeneration
		let version = try await executableVersion()
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		try validateProtocolVersion(version)

		guard let executable = executableOverride ?? Self.executableURL()
		else
		{
			throw AppServerError.executableMissing
		}
		let process = Process()
		process.executableURL = executable
		process.arguments = ["app-server", "--stdio"]

		let stdin = Pipe()
		let stdout = Pipe()
		let stderr = Pipe()
		process.standardInput = stdin
		process.standardOutput = stdout
		process.standardError = stderr

		self.process = process
		input = stdin.fileHandleForWriting
		output = stdout.fileHandleForReading
		errorOutput = stderr.fileHandleForReading

		let stream = AsyncStream<Data>
		{
			continuation in
			self.frameContinuation = continuation
		}
		do
		{
			try process.run()
			messageWriter = try ProtocolMessageWriter(
				handle: stdin.fileHandleForWriting,
				reportIOFailure:
				{
					[weak self] failure in
					Task
					{
						@MainActor [weak self] in
						self?.transportWriteFailed(
							failure,
							generation: generation
						)
					}
				}
			)
			let diagnosticGeneration = try startProcessDiagnostics(
				for: process,
				stderr: stderr.fileHandleForReading,
				version: version
			)
			startMessageDelivery(
				from: stream,
				stdout: stdout.fileHandleForReading,
				generation: generation,
				diagnosticGeneration: diagnosticGeneration
			)
			try await initializeProtocol(for: generation)
		}
		catch
		{
			if generation == connectionGeneration
			{
				disconnect()
			}
			throw error
		}
	}

	private func startProcessDiagnostics(
		for process: Process,
		stderr: FileHandle,
		version: String
	) throws -> UUID
	{
		let diagnosticGeneration = diagnostics.beginConnection(cliVersion: version)
		let stderrReader = try StderrReader(
			handle: stderr,
			diagnostics: diagnostics,
			generation: diagnosticGeneration
		)
		self.stderrReader = stderrReader
		stderrReader.start()
		process.terminationHandler =
		{
			[weak self, weak process] _ in
			Task
			{
				@MainActor [weak self, weak process] in
				guard let self, let process, self.process === process
				else
				{
					return
				}
				self.captureTerminationDiagnostics(
					process,
					for: diagnosticGeneration,
					using: stderrReader,
					message: "Codex app-server exited."
				)
			}
		}
		return diagnosticGeneration
	}

	private func startMessageDelivery(
		from stream: AsyncStream<Data>,
		stdout: FileHandle,
		generation: UUID,
		diagnosticGeneration: UUID
	)
	{
		let lineFramer = JSONLineFramer()
		messageTask = Task.detached
		{
			[weak self, lineFramer] in
			for await data in stream
			{
				if data.isEmpty
				{
					await self?.failedForConnection(
						generation,
						diagnosticGeneration: diagnosticGeneration,
						message: "Codex app-server closed its output."
					)
					return
				}
				for line in lineFramer.append(data)
				{
					guard let value = (try? JSONSerialization
						.jsonObject(with: line)) as? [String: Any]
					else
					{
						await self?.reportInvalidMessage(for: generation)
						continue
					}
					let message = ProtocolJSONPayload(value: value)
					await self?.receiveMessage(
						message.value,
						for: generation
					)
				}
			}
		}

		let frameContinuation = self.frameContinuation
		stdout.readabilityHandler =
		{
			handle in
			frameContinuation?.yield(handle.availableData)
		}
	}

	private func initializeProtocol(for generation: UUID) async throws
	{
		_ = try await request(
			"initialize",
			params: [
				"clientInfo": [
					"name": "codex_gui_appkit",
					"title": "Codex GUI AppKit",
					"version": "0.1.0",
				],
				"capabilities": ["experimentalApi": true, "requestAttestation": false],
			]
		)
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		let initialized = try send(["method": "initialized"])
		try await initialized.wait()
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
	}

	func request(
		_ method: String,
		params: [String: Any]
	) async throws -> [String: Any]
	{
		guard process?.isRunning == true
		else
		{
			throw AppServerError.disconnected
		}
		let requestID = nextID
		nextID += 1
		let generation = connectionGeneration
		try Task.checkCancellation()
		let ticket = makeRequestWriteTicket(
			for: requestID,
			generation: generation
		)

		let message: ProtocolJSONPayload = try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				continuation in
				pending[requestID] = continuation
				// Install the deadline before the writer can serialize or touch a full pipe.
				installRequestDeadline(
					requestID,
					method: method,
					generation: generation
				)

				do
				{
					requestWrites[requestID] = try enqueueMessage(
						["id": requestID, "method": method, "params": params],
						ticket: ticket
					)
				}
				catch
				{
					requestTimeouts.removeValue(forKey: requestID)?.cancel()
					pending.removeValue(forKey: requestID)?.resume(throwing: error)
				}
			}
		}
		onCancel:
		{
			// The writer must observe cancellation before actor cleanup can run.
			ticket.fail(CancellationError())
			Task
			{
				@MainActor [weak self] in
				self?.cancelRequest(
					requestID,
					generation: generation
				)
			}
		}

		return message.value
	}

	private func makeRequestWriteTicket(
		for requestID: Int,
		generation: UUID
	) -> ProtocolWriteTicket
	{
		ProtocolWriteTicket(completion:
			{
				[weak self] result in
				guard case .failure(let failure) = result
				else
				{
					return
				}
				Task
				{
					@MainActor [weak self] in
					self?.requestWriteFailed(
						requestID,
						failure: failure,
						generation: generation
					)
				}
			})
	}

	private func installRequestDeadline(
		_ requestID: Int,
		method: String,
		generation: UUID
	)
	{
		let timeout = requestTimeout
		requestTimeouts[requestID] = Task
		{
			[weak self] in
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled
			else
			{
				return
			}
			self?.timeOutRequest(
				requestID,
				method: method,
				generation: generation
			)
		}
	}

	@discardableResult
	func send(_ value: [String: Any]) throws -> ProtocolWriteTicket
	{
		let generation = connectionGeneration
		let ticket = ProtocolWriteTicket(completion:
			{
				[weak self] result in
				guard case .failure(let failure) = result
				else
				{
					return
				}
				Task
				{
					@MainActor [weak self] in
					self?.transportWriteFailed(
						failure,
						generation: generation
					)
				}
			})
		return try enqueueMessage(
			value,
			ticket: ticket
		)
	}

	func enqueueMessage(
		_ value: [String: Any],
		ticket: ProtocolWriteTicket = ProtocolWriteTicket()
	) throws -> ProtocolWriteTicket
	{
		guard let messageWriter, process?.isRunning == true
		else
		{
			throw ProtocolWriteFailure(
				cause: AppServerError.disconnected,
				mayHaveBeenSent: false,
				requiresDisconnect: false
			)
		}
		let payload: ProtocolJSONValue
		do
		{
			payload = try ProtocolJSONValue(snapshot: value)
		}
		catch
		{
			throw ProtocolWriteFailure(
				cause: error,
				mayHaveBeenSent: false,
				requiresDisconnect: false
			)
		}
		return messageWriter.enqueue(
			payload,
			ticket: ticket
		)
	}

	func transportWriteFailed(
		_ failure: ProtocolWriteFailure,
		generation: UUID
	)
	{
		guard generation == connectionGeneration
		else
		{
			return
		}
		if failure.requiresDisconnect
		{
			failed("Codex app-server input failed: \(failure.localizedDescription)")
		}
	}

	private func receiveMessage(
		_ message: [String: Any],
		for generation: UUID
	)
	{
		guard generation == connectionGeneration
		else
		{
			return
		}
		if let method = message["method"] as? String
		{
			guard let parameters = message["params"] as? [String: Any]
			else
			{
				reportInvalidMessage(for: generation)
				return
			}
			if let id = message["id"]
			{
				receiveServerRequest(
					id: id,
					method: method,
					parameters: parameters
				)
			}
			else
			{
				receiveNotification(
					method: method,
					parameters: parameters
				)
			}
			return
		}
		completePendingRequest(from: message)
	}

	private func completePendingRequest(from message: [String: Any])
	{
		if let wireID = message["id"].flatMap(JSONRPCRequestID.init(json:)),
			case .integer(let integerID) = wireID, let id = Int(exactly: integerID),
			let continuation = pending.removeValue(forKey: id)
		{
			requestTimeouts.removeValue(forKey: id)?.cancel()
			requestWrites.removeValue(forKey: id)
			if let result = message["result"] as? [String: Any]
			{
				// The transport already decoded this JSON object off the main actor.
				continuation.resume(returning: ProtocolJSONPayload(value: result))
			}
			else if message["result"] == nil,
					let error = message["error"] as? [String: Any],
					let code = error["code"].flatMap(JSONRPCRequestID.init(json:)),
					case .integer = code,
					let errorMessage = error["message"] as? String
			{
				continuation.resume(throwing: AppServerError.requestRejected(errorMessage))
			}
			else
			{
				continuation.resume(
					throwing: AppServerError.protocolError("Invalid response from app-server")
				)
			}
			return
		}
	}

	func reportInvalidMessage(for generation: UUID)
	{
		guard generation == connectionGeneration
		else
		{
			return
		}
		onEvent?(
			.error(
				threadId: "",
				turnId: "",
				message: "Invalid app-server message.",
				willRetry: false
			)
		)
	}

	private func failedForConnection(
		_ generation: UUID,
		diagnosticGeneration: UUID,
		message: String
	) async
	{
		guard generation == connectionGeneration
		else
		{
			return
		}
		// Pipe EOF can arrive just before Foundation reports the child's exit.
		// Give that notification a bounded window without delaying the main actor.
		for _ in 0 ..< 10 where process?.isRunning == true
		{
			try? await Task.sleep(for: .milliseconds(10))
			guard generation == connectionGeneration
			else
			{
				return
			}
		}
		if let process, !process.isRunning, let stderrReader
		{
			captureTerminationDiagnostics(
				process,
				for: diagnosticGeneration,
				using: stderrReader,
				message: message
			)
			return
		}
		failed(message)
	}

	private func captureTerminationDiagnostics(
		_ process: Process,
		for generation: UUID,
		using reader: StderrReader,
		message: String
	)
	{
		guard diagnosticsFinalizing.insert(generation).inserted
		else
		{
			return
		}
		reader.finish(exitCode: process.terminationStatus)
		{
			[weak self, weak process] in
			Task
			{
				@MainActor [weak self, weak process] in
				guard let self, let process, self.process === process
				else
				{
					return
				}
				self.diagnosticsFinalizing.remove(generation)
				self.failed(message)
			}
		}
	}

	private func timeOutRequest(
		_ id: Int,
		method: String,
		generation: UUID
	)
	{
		guard generation == connectionGeneration, let continuation = pending.removeValue(forKey: id)
		else
		{
			return
		}
		requestTimeouts.removeValue(forKey: id)?.cancel()
		let failure = requestWrites.removeValue(forKey: id)?
			.fail(AppServerError.requestTimedOut(method))
		if let failure, !failure.mayHaveBeenSent
		{
			continuation.resume(throwing: failure)
		}
		else
		{
			continuation.resume(throwing: AppServerError.requestTimedOut(method))
		}
		if let failure
		{
			transportWriteFailed(
				failure,
				generation: generation
			)
		}
	}

	private func cancelRequest(
		_ id: Int,
		generation: UUID
	)
	{
		guard generation == connectionGeneration, let continuation = pending.removeValue(forKey: id)
		else
		{
			return
		}
		requestTimeouts.removeValue(forKey: id)?.cancel()
		let failure = requestWrites.removeValue(forKey: id)?.fail(CancellationError())
		continuation.resume(throwing: failure ?? ProtocolWriteFailure(
			cause: CancellationError(),
			mayHaveBeenSent: false,
			requiresDisconnect: false
		))
		if let failure
		{
			transportWriteFailed(
				failure,
				generation: generation
			)
		}
	}

	private func requestWriteFailed(
		_ id: Int,
		failure: ProtocolWriteFailure,
		generation: UUID
	)
	{
		guard generation == connectionGeneration
		else
		{
			return
		}
		requestTimeouts.removeValue(forKey: id)?.cancel()
		requestWrites.removeValue(forKey: id)
		pending.removeValue(forKey: id)?.resume(throwing: failure)
		transportWriteFailed(
			failure,
			generation: generation
		)
	}

	private func failed(_ message: String)
	{
		guard process != nil
		else
		{
			return
		}
		disconnect()
		onDisconnect?(message)
	}

	func disconnect()
	{
		connectionGeneration = UUID()
		stopProcessTransport()

		interactions.removeAll()
		answeredInteractions.removeAll()

		failPendingRequests()
	}

	private func stopProcessTransport()
	{
		messageWriter?.retire()
		messageWriter = nil
		output?.readabilityHandler = nil
		stderrReader?.cancel()
		stderrReader = nil
		diagnosticsFinalizing.removeAll()
		errorOutput?.readabilityHandler = nil
		frameContinuation?.finish()
		frameContinuation = nil
		messageTask?.cancel()
		messageTask = nil
		process?.terminationHandler = nil
		if process?.isRunning == true
		{
			process?.terminate()
		}
		process = nil
		input = nil
		output = nil
		errorOutput = nil

	}

	private func failPendingRequests()
	{
		let pendingRequests = pending
		pending.removeAll()
		let writes = requestWrites
		requestWrites.removeAll()
		for timeout in requestTimeouts.values
		{
			timeout.cancel()
		}
		requestTimeouts.removeAll()
		for (id, continuation) in pendingRequests
		{
			let failure = writes[id]?.fail(AppServerError.disconnected)
			continuation.resume(throwing: failure ?? ProtocolWriteFailure(
				cause: AppServerError.disconnected,
				mayHaveBeenSent: false,
				requiresDisconnect: false
			))
		}
	}
}
