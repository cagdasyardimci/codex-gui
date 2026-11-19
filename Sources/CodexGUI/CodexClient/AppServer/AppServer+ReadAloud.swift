import Foundation

extension AppServer
{
	func readAloudAvailable(in directory: URL) async throws -> Bool
	{
		try await realtimeWebSocketAvailable(in: directory)
	}

	func realtimeWebSocketAvailable(in directory: URL) async throws -> Bool
	{
		guard try await realtimeWebSocketCredentialsAvailable(in: directory)
		else
		{
			return false
		}
		return try await hasRealtimeAudioVoices()
	}

	func realtimeWebSocketCredentialsAvailable(in directory: URL) async throws -> Bool
	{
		guard let config = try await realtimeVoiceConfiguration(in: directory)
		else
		{
			return false
		}
		let providerID = config["model_provider"] as? String ?? "openai"
		let providers = config["model_providers"] as? [String: [String: Any]] ?? [:]
		let provider = providers[providerID] ?? [:]
		if let envName = provider["env_key"] as? String
		{
			// Codex requires a configured provider key before considering other credentials.
			guard let key = subprocessEnvironmentValue(envName),
					!key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			else
			{
				return false
			}
		}
		else
		{
			let bearer = provider["experimental_bearer_token"] as? String ?? ""
			let isOpenAI = providerID == "openai" || provider["name"] as? String == "OpenAI"
			let openAIKey = isOpenAI ? subprocessEnvironmentValue("OPENAI_API_KEY") ?? "" : ""
			if bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
				openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
				try await accountStatus().type != "apiKey"
			{
				return false
			}
		}
		return true
	}

	func realtimeVoiceConfiguration(in directory: URL) async throws -> [String: Any]?
	{
		let response = try await request(
			"config/read",
			params: ["includeLayers": false, "cwd": directory.path]
		)
		guard let config = response["config"] as? [String: Any],
				(config["features"] as? [String: Any])?["realtime_conversation"] as? Bool != false
		else
		{
			return nil
		}
		return config
	}

	func hasRealtimeAudioVoices() async throws -> Bool
	{
		let voices = try await request(
			"thread/realtime/listVoices",
			params: [:]
		)
		return try !Self.realtimeAudioVoices(from: voices).isEmpty
	}

	func createReadAloudThread(in directory: URL) async throws -> String
	{
		let generation = connectionGeneration
		let response = try await request(
			"thread/start",
			params: [
				"cwd": directory.path,
				"ephemeral": true,
				"approvalPolicy": "never",
				"sandbox": "read-only"
			]
		)
		guard generation == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		guard let thread = response["thread"] as? [String: Any], let id = thread["id"] as? String,
				!id.isEmpty
		else
		{
			throw ReadAloudError.invalidResponse
		}
		readAloudThreadGenerations[id] = generation
		return id
	}

	func startReadAloudSession(
		threadID: String,
		voice: String? = nil
	) async throws
	{
		guard readAloudThreadGenerations[threadID] == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		var params: [String: Any] = [
			"threadId": threadID,
			"version": Self.realtimeAudioVersion,
			"outputModality": "audio",
			"includeStartupContext": false,
			"clientManagedHandoffs": true,
			"flushTranscriptTailOnSessionEnd": false,
			"backendReasoningStatus": false,
			"transport": ["type": "websocket"],
		]
		params["voice"] = voice
		_ = try await request(
			"thread/realtime/start",
			params: params
		)
	}

	func appendReadAloudSpeech(
		threadID: String,
		text: String
	) async throws
	{
		guard readAloudThreadGenerations[threadID] == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		_ = try await request(
			"thread/realtime/appendSpeech",
			params: ["threadId": threadID, "text": text]
		)
	}

	func retireReadAloudThread(threadID: String) async
	{
		let generation = connectionGeneration
		guard readAloudThreadGenerations[threadID] == generation
		else
		{
			return
		}
		_ = try? await request(
			"thread/realtime/stop",
			params: ["threadId": threadID]
		)
		guard generation == connectionGeneration,
				readAloudThreadGenerations[threadID] == generation
		else
		{
			return
		}
		_ = try? await request(
			"thread/unsubscribe",
			params: ["threadId": threadID]
		)
		guard generation == connectionGeneration,
				readAloudThreadGenerations[threadID] == generation
		else
		{
			return
		}
		readAloudThreadGenerations.removeValue(forKey: threadID)
	}

	func receiveReadAloudNotification(
		method: String,
		parameters: [String: Any]
	) -> Bool
	{
		guard let threadID = parameters["threadId"] as? String,
				readAloudThreadGenerations[threadID] == connectionGeneration
		else
		{
			return false
		}
		let event: ReadAloudBackendEvent?
		switch method
		{
		case "thread/realtime/started": event =
			.started(version: parameters["version"] as? String ?? "")
		case "thread/realtime/outputAudio/delta":
			guard let raw = parameters["audio"] as? [String: Any],
					let data = raw["data"] as? String,
					let rate = raw["sampleRate"] as? Int,
					let channels = raw["numChannels"] as? Int
			else
			{
				onReadAloudEvent?(threadID, .failed("Invalid realtime audio frame.")); return true
			}
			if data.isEmpty
			{
				return true
			}
			do
			{
				event = .audio(try ReadAloudAudioChunk(
					base64Data: data,
					sampleRate: rate,
					numChannels: channels,
					samplesPerChannel: raw["samplesPerChannel"] as? Int
				))
			}
			catch
			{
				event = .failed("Invalid realtime audio frame.")
			}
		case "thread/realtime/transcript/done": event = parameters["role"] as? String ==
			"assistant" ? .segmentFinished : nil
		case "thread/realtime/error": event = .failed(BackendDiagnosticsBuffer
				.displaySafeText(parameters["message"] as? String ?? "Realtime speech failed."))
		case "thread/realtime/closed": event = .closed
		case "thread/realtime/itemAdded":
			let item = parameters["item"] as? [String: Any]
			event = item?["type"] as? String == "handoff_request" ?
				.failed("Unexpected realtime handoff.") : nil
		default: event = nil
		}
		if let event
		{
			onReadAloudEvent?(threadID, event)
		}
		return true
	}
}
