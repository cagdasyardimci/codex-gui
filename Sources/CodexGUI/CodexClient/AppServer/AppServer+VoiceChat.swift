import Foundation

extension AppServer
{
	func chatGPTVoiceAvailable(in directory: URL) async throws -> Bool
	{
		guard let config = try await realtimeVoiceConfiguration(in: directory),
				(config["model_provider"] as? String ?? "openai") == "openai"
		else
		{
			return false
		}
		return try await hasRealtimeAudioVoices()
	}

	func prepareVoiceChat(
		threadID: String?,
		projectPath: String,
		model: String?,
		effort: String?,
		preferences: RunPreferences
	) async throws -> ThreadSummary
	{
		if let threadID
		{
			let detail = try await resumeThread(
				id: threadID,
				expectedDirectory: URL(fileURLWithPath: projectPath)
			)
			return detail.summary
		}
		var summary = try await createVoiceChat(
			projectPath: projectPath,
			model: model,
			effort: effort,
			preferences: preferences
		)
		try Task.checkCancellation()
		let name = "New voice chat"
		try await renameThread(
			id: summary.id,
			name: name
		)
		summary.name = name
		return summary
	}

	private func createVoiceChat(
		projectPath: String,
		model: String?,
		effort: String?,
		preferences: RunPreferences
	) async throws -> ThreadSummary
	{
		let sandbox: String
		switch preferences.sandboxPolicy
		{
		case .readOnly: sandbox = "read-only"
		case .workspaceWrite, .configuredWorkspaceWrite: sandbox = "workspace-write"
		case .dangerFullAccess: sandbox = "danger-full-access"
		}

		var config: [String: Any] = ["realtime.type": "conversational"]
		config["model_reasoning_effort"] = effort
		config["sandbox_workspace_write.network_access"] =
			preferences.sandboxPolicy.protocolValue["networkAccess"]
		var parameters: [String: Any] = [
			"cwd": projectPath,
			"approvalPolicy": preferences.approvalPolicy.rawValue,
			"approvalsReviewer": preferences.approvalsReviewer.rawValue,
			"sandbox": sandbox,
			"serviceTier": preferences.serviceTierForTurn,
			"config": config,
			"historyMode": "paginated",
		]
		parameters["model"] = model
		let result = try await request(
			"thread/start",
			params: parameters
		)
		guard let thread = result["thread"] as? [String: Any],
				let summary = ThreadSummary(json: thread),
				summary.cwd == projectPath, summary.historyMode == "paginated"
		else
		{
			throw AppServerError.protocolError("Invalid voice conversation.")
		}
		return summary
	}

	func startVoiceChat(
		threadID: String,
		sessionID: UUID,
		offer: String?,
		voice: String
	) async throws
	{
		_ = try await request(
			"thread/realtime/start",
			params: [
				"threadId": threadID,
				"voiceSessionId": sessionID.uuidString,
				"outputModality": "audio",
				"version": Self.realtimeAudioVersion,
				"voice": voice,
				"transport": offer.map
				{
					["type": "webrtc", "sdp": $0]
				} ?? ["type": "websocket"],
				"flushTranscriptTailOnSessionEnd": true,
				"codexResponseHandoffMode": "bemTags",
			]
		)
	}

	func appendVoiceAudio(
		threadID: String,
		pcm: Data
	) async throws
	{
		_ = try await request(
			"thread/realtime/appendAudio",
			params: [
				"threadId": threadID,
				"audio": [
					"data": pcm.base64EncodedString(),
					"sampleRate": VoiceChatMicrophone.sampleRate,
					"numChannels": 1,
					"samplesPerChannel": pcm.count / MemoryLayout<Int16>.size,
				],
			]
		)
	}

	func appendVoiceText(
		threadID: String,
		text: String
	) async throws
	{
		_ = try await request(
			"thread/realtime/appendText",
			params: ["threadId": threadID, "text": text]
		)
	}

	func stopVoiceChat(threadID: String) async throws
	{
		_ = try await request(
			"thread/realtime/stop",
			params: ["threadId": threadID]
		)
	}

	fileprivate enum VoiceTimelineEntry
	{
		case turn(
			String,
			started: Bool
		)
		case start
		case close
		case speech(VoiceChatSegment)
	}

	struct VoiceTimelineWindow
	{
		enum Coverage: Equatable
		{
			case latest
			case throughTurn(String)
			case entireThread
		}

		fileprivate var pages: [(voiceActive: Bool?, entries: [VoiceTimelineEntry])] = []
		fileprivate var startedTurnIDs: Set<String> = []
		fileprivate var nextCursor: String?
		fileprivate var cursors = PaginationCursorTracker(
			repeatedCursorMessage: "Codex repeated the voice history cursor."
		)

		func covers(_ coverage: Coverage) -> Bool
		{
			guard !pages.isEmpty
			else
			{
				return false
			}
			if nextCursor == nil
			{
				return true
			}
			switch coverage
			{
			case .latest: return true
			case .throughTurn(let turnID): return startedTurnIDs.contains(turnID)
			case .entireThread: return false
			}
		}

		var history: VoiceChatHistory
		{
			// Pages are newest first, but positions within each page run oldest first.
			var history = VoiceChatHistory()
			var seenTurns: Set<String> = []
			var precedingTurnID: String?
			var voiceActive = false
			for page in pages.reversed()
			{
				voiceActive = page.voiceActive ?? voiceActive
				for entry in page.entries
				{
					switch entry
					{
					case .turn(
						let turnID,
						_
					):
						precedingTurnID = turnID
						if seenTurns.insert(turnID).inserted
						{
							history.orderedTurnIDs.append(turnID)
						}
						if voiceActive
						{
							history.voiceTurnIDs.insert(turnID)
						}
					case .start:
						voiceActive = true
					case .close:
						voiceActive = false
					case .speech(var segment):
						// Speech before the first known turn may belong to an older page.
						if precedingTurnID != nil || nextCursor == nil
						{
							segment.precedingTurnID = precedingTurnID
							history.segments.append(segment)
						}
					}
				}
			}
			return history
		}
	}

	func loadVoiceTimeline(
		threadID: String,
		covering coverage: VoiceTimelineWindow.Coverage,
		extending window: VoiceTimelineWindow = VoiceTimelineWindow()
	) async throws -> VoiceTimelineWindow
	{
		var window = window
		while !window.covers(coverage)
		{
			try Task.checkCancellation()
			var params: [String: Any] = ["threadId": threadID, "limit": 100]
			params["cursor"] = window.nextCursor
			let response: [String: Any]
			do
			{
				response = try await request(
					"thread/timeline/list",
					params: params
				)
			}
			catch AppServerError.requestTimedOut
			{
				try Task.checkCancellation()
				// A timed-out read is safe to repeat at the same cursor once.
				response = try await request(
					"thread/timeline/list",
					params: params
				)
			}
			guard let data = response["data"] as? [[String: Any]]
			else
			{
				throw AppServerError.protocolError("Codex returned invalid voice history.")
			}
			let entries = data.compactMap(decodeVoiceTimelineEntry)
			window.nextCursor = try window.cursors.advance(to: response["nextCursor"] as? String)
			window.pages.append((
				response["activeRealtimeSessionAtPageStart"].map
				{
					$0 is String
				},
				entries
			))
			for case .turn(
				let id,
				started: true
			) in entries
			{
				window.startedTurnIDs.insert(id)
			}
		}
		return window
	}

	private func decodeVoiceTimelineEntry(_ entry: [String: Any]) -> VoiceTimelineEntry?
	{
		if let turnID = entry["turnId"] as? String
		{
			return .turn(
				turnID,
				started: entry["type"] as? String == "turnStarted"
			)
		}
		guard entry["type"] as? String == "realtime",
				let item = entry["item"] as? [String: Any]
		else
		{
			return nil
		}
		switch item["type"] as? String
		{
		case "realtimeSessionStarted": return .start
		case "realtimeSessionClosed": return .close
		default: return voiceChatSegment(item).map(VoiceTimelineEntry.speech)
		}
	}

	private func voiceChatSegment(_ item: [String: Any]) -> VoiceChatSegment?
	{
		guard item["type"] as? String == "transcriptSegment",
				let id = item["id"] as? String, let role = item["role"] as? String,
				role == "user" || role == "assistant", let text = item["text"] as? String
		else
		{
			return nil
		}
		return VoiceChatSegment(
			id: id,
			isUser: role == "user",
			text: text
		)
	}

	func receiveVoiceChatNotification(
		method: String,
		threadID: String,
		parameters: [String: Any]
	)
	{
		guard let observer = voiceChatObservers[threadID]
		else
		{
			return
		}
		switch method
		{
		case "thread/realtime/started": observer(.started)
		case "thread/realtime/closed":
			observer(parameters["reason"] as? String == "requested" ? .requestedStop : .closed)
		case "thread/realtime/sdp":
			if let sdp = parameters["sdp"] as? String, !sdp.isEmpty
			{
				observer(.sdp(sdp))
			}
		case "thread/realtime/error":
			observer(.failed(parameters["message"] as? String ?? "Voice session failed."))
		case "thread/realtime/item/started", "thread/realtime/item/completed":
			if let item = parameters["item"] as? [String: Any],
				let segment = voiceChatSegment(item)
			{
				observer(.segment(segment))
			}
		case "thread/realtime/item/transcript/delta":
			if let id = parameters["itemId"] as? String, let delta = parameters["delta"] as? String
			{
				observer(.transcriptDelta(
					itemID: id,
					text: delta
				))
			}
		case "thread/realtime/transcript/delta", "thread/realtime/transcript/done":
			let isFinal = method == "thread/realtime/transcript/done"
			if let role = parameters["role"] as? String, role == "user" || role == "assistant",
				let text = parameters[isFinal ? "text" : "delta"] as? String
			{
				observer(.legacyTranscript(
					isUser: role == "user",
					text: text,
					isFinal: isFinal
				))
			}
		case "thread/realtime/itemAdded":
			if let item = parameters["item"] as? [String: Any],
				["input_audio_buffer.speech_started", "response.cancelled"].contains(
				item["type"] as? String ?? ""
				)
			{
				observer(.interrupted)
			}
		case "thread/realtime/outputAudio/delta":
			if let audio = parameters["audio"] as? [String: Any],
				let data = audio["data"] as? String, let rate = audio["sampleRate"] as? Int,
				let channels = audio["numChannels"] as? Int,
				let chunk = try? ReadAloudAudioChunk(
				base64Data: data,
				sampleRate: rate,
				numChannels: channels,
				samplesPerChannel: audio["samplesPerChannel"] as? Int
				)
			{
				observer(.audio(chunk))
			}
		default: break
		}
	}
}
