import Foundation

extension AppServer
{
	func readAloudAvailable(in directory: URL) async throws -> Bool
	{
		let response = try await request(
			"config/read",
			params: ["includeLayers": false, "cwd": directory.path]
		)
		guard let config = response["config"] as? [String: Any]
		else
		{
			return false
		}
		let providerName = config["model_provider"] as? String ?? "openai"
		let providers = config["model_providers"] as? [String: [String: Any]] ?? [:]
		let provider = providers[providerName] ?? [:]
		let features = config["features"] as? [String: Any] ?? [:]
		guard features["realtime_conversation"] as? Bool != false
		else
		{
			return false
		}
		let account = try await accountStatus()
		let environment = ProcessInfo.processInfo.environment
		let envName = provider["env_key"] as? String
		let hasEnvironmentKey = envName.flatMap
		{
			environment[$0]
		}.map
		{
			!$0.isEmpty
		} ?? false
		let bearer = provider["experimental_bearer_token"] as? String ?? ""
		let hasOpenAIKey = providerName == "openai" && !(environment["OPENAI_API_KEY"] ?? "")
			.isEmpty
		guard hasEnvironmentKey || !bearer.isEmpty || account.type == "apiKey" || hasOpenAIKey
		else
		{
			return false
		}
		let voices = try await request(
			"thread/realtime/listVoices",
			params: [:]
		)
		return !(((voices["voices"] as? [String: Any])?["v3"] as? [String]) ?? []).isEmpty
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

	func startReadAloudSession(threadID: String) async throws
	{
		guard readAloudThreadGenerations[threadID] == connectionGeneration
		else
		{
			throw AppServerError.disconnected
		}
		_ = try await request(
			"thread/realtime/start",
			params: [
				"threadId": threadID,
				"version": "v3",
				"outputModality": "audio",
				"includeStartupContext": false,
				"clientManagedHandoffs": true,
				"flushTranscriptTailOnSessionEnd": false,
				"backendReasoningStatus": false,
				"transport": ["type": "websocket"]
			]
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
