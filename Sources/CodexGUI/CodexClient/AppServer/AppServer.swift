import Foundation

private struct ParsedProtocolMessage: @unchecked Sendable
{
	let value: [String: Any]
}

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
	private var output: FileHandle?
	private var errorOutput: FileHandle?
	private var stderrReader: StderrReader?
	private var diagnosticsFinalizing = Set<UUID>()
	private var frameContinuation: AsyncStream<Data>.Continuation?
	private var messageTask: Task<Void, Never>?
	private var nextID = 1
	private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
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
			let diagnosticGeneration = diagnostics.beginConnection(cliVersion: version)
			let stderrReader = try StderrReader(
				handle: stderr.fileHandleForReading,
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
						let message = ParsedProtocolMessage(value: value)
						await self?.receiveMessage(
							message.value,
							for: generation
						)
					}
				}
			}

			let frameContinuation = self.frameContinuation
			stdout.fileHandleForReading.readabilityHandler =
			{
				handle in
				frameContinuation?.yield(handle.availableData)
			}

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
			try send(["method": "initialized"])
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
		let id = nextID
		nextID += 1
		let timeout = requestTimeout
		let data: Data = try await withCheckedThrowingContinuation
		{
			continuation in
			pending[id] = continuation
			do
			{
				try send(["id": id, "method": method, "params": params])
				requestTimeouts[id] = Task
				{
					[weak self] in
					try? await Task.sleep(for: timeout)
					guard !Task.isCancelled
					else
					{
						return
					}
					self?.timeOutRequest(
						id,
						method: method
					)
				}
			}
			catch
			{
				pending.removeValue(forKey: id)
				continuation.resume(throwing: error)
			}
		}
		guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		else
		{
			throw AppServerError.protocolError("Invalid response from app-server")
		}
		return result
	}

	func send(_ value: [String: Any]) throws
	{
		guard let input, process?.isRunning == true
		else
		{
			throw AppServerError.disconnected
		}
		var data = try JSONSerialization.data(withJSONObject: value)
		data.append(0x0A)
		try input.write(contentsOf: data)
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
		if let wireID = message["id"].flatMap(JSONRPCRequestID.init(json:)),
			case .integer(let integerID) = wireID, let id = Int(exactly: integerID),
			let continuation = pending.removeValue(forKey: id)
		{
			requestTimeouts.removeValue(forKey: id)?.cancel()
			if let result = message["result"] as? [String: Any],
				let data = try? JSONSerialization.data(withJSONObject: result)
			{
				continuation.resume(returning: data)
			}
			else
			{
				let error = message["error"] as? [String: Any]
				continuation.resume(
					throwing: AppServerError.protocolError(
						error?["message"] as? String ?? "Invalid response from app-server"
					)
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
		method: String
	)
	{
		requestTimeouts.removeValue(forKey: id)
		pending.removeValue(forKey: id)?.resume(throwing: AppServerError.requestTimedOut(method))
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

		interactions.removeAll()
		answeredInteractions.removeAll()

		let operations = pending
		pending.removeAll()
		for timeout in requestTimeouts.values
		{
			timeout.cancel()
		}
		requestTimeouts.removeAll()
		for continuation in operations.values
		{
			continuation.resume(throwing: AppServerError.disconnected)
		}
	}
}
