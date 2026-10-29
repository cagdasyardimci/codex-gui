import Foundation

// Decodes notifications and publishes events on the session main actor.
extension AppServer
{
	func receiveNotification(
		method: String,
		parameters: [String: Any]
	)
	{
		let threadID = parameters["threadId"] as? String ?? ""
		if receiveAutomaticTitleNotification(
			method: method,
			parameters: parameters
		)
		{
			return
		}
		let turnID = parameters["turnId"] as? String ?? ""
		switch method
		{
		case "thread/queue/changed":
			guard !threadID.isEmpty
			else
			{
				return
			}
			onEvent?(.threadQueueChanged(threadId: threadID))
		case "thread/name/updated":
			guard !threadID.isEmpty
			else
			{
				return
			}
			onEvent?(.threadNameUpdated(
				threadId: threadID,
				name: parameters["threadName"] as? String
			))
		case "thread/tokenUsage/updated":
			guard !threadID.isEmpty, !turnID.isEmpty,
					let rawUsage = parameters["tokenUsage"] as? [String: Any],
					let usage = ThreadTokenUsage(json: rawUsage)
			else
			{
				return
			}
			onEvent?(.tokenUsageUpdated(
				threadId: threadID,
				turnId: turnID,
				usage: usage
			))
		case "thread/settings/updated":
			guard !threadID.isEmpty,
					let rawSettings = parameters["threadSettings"] as? [String: Any],
					let settings = ThreadSettings(json: rawSettings)
			else
			{
				return
			}
			onEvent?(.threadSettingsUpdated(
				threadId: threadID,
				settings: settings
			))
		case "thread/status/changed":
			guard !threadID.isEmpty,
					let rawStatus = parameters["status"] as? [String: Any],
					let status = ThreadStatus(json: rawStatus)
			else
			{
				return
			}
			onEvent?(.threadStatusChanged(
				threadId: threadID,
				status: status
			))
		case "thread/compacted":
			guard !threadID.isEmpty, !turnID.isEmpty
			else
			{
				return
			}
			onEvent?(.contextCompacted(
				threadId: threadID,
				turnId: turnID
			))
		case "turn/started":
			if let turn = (parameters["turn"] as? [String: Any]).flatMap(CodexTurn.init(json:))
			{
				onEvent?(.turnStarted(
					threadId: threadID,
					turn: turn
				))
			}
		case "turn/completed":
			if let turn = (parameters["turn"] as? [String: Any]).flatMap(CodexTurn.init(json:))
			{
				onEvent?(.turnCompleted(
					threadId: threadID,
					turn: turn
				))
			}
		case "item/started", "item/completed":
			guard let item = (parameters["item"] as? [String: Any]).flatMap(CodexItem.init(json:))
			else
			{
				return
			}
			if method == "item/started"
			{
				onEvent?(.itemStarted(
					threadId: threadID,
					turnId: turnID,
					item: item
				))
			}
			else
			{
				onEvent?(.itemCompleted(
					threadId: threadID,
					turnId: turnID,
					item: item
				))
			}
		case "item/agentMessage/delta":
			onEvent?(
				.agentMessageDelta(
					threadId: threadID,
					turnId: turnID,
					itemId: parameters["itemId"] as? String ?? "",
					text: parameters["delta"] as? String ?? ""
				)
			)
		case "item/commandExecution/outputDelta":
			onEvent?(
				.commandOutputDelta(
					threadId: threadID,
					turnId: turnID,
					itemId: parameters["itemId"] as? String ?? "",
					text: parameters["delta"] as? String ?? ""
				)
			)
		case "item/fileChange/patchUpdated":
			onEvent?(
				.fileChangeUpdated(
					threadId: threadID,
					turnId: turnID,
					itemId: parameters["itemId"] as? String ?? "",
					changes: (parameters["changes"] as? [[String: Any]] ?? [])
						.compactMap(FileChange.init(json:))
				)
			)
		case "turn/diff/updated":
			onEvent?(
				.diffUpdated(
					threadId: threadID,
					turnId: turnID,
					diff: parameters["diff"] as? String ?? ""
				)
			)
		case "turn/plan/updated":
			if let update = TurnPlanUpdate(json: parameters)
			{
				onEvent?(.planUpdated(update))
			}
		case "item/mcpToolCall/progress":
			guard let itemId = parameters["itemId"] as? String,
					let message = parameters["message"] as? String
			else
			{
				return
			}
			onEvent?(
				.toolProgress(
					threadId: threadID,
					turnId: turnID,
					itemId: itemId,
					message: message
				)
			)
		case "serverRequest/resolved":
			resolvePendingInteraction(from: parameters)
		case "remoteControl/status/changed":
			if let status: RemoteControlStatus = try? decodeRemoteControl(parameters)
			{
				onEvent?(.remoteControlStatusChanged(status))
			}
		case "account/updated", "account/login/completed":
			onEvent?(.accountUpdated)
		case "skills/changed":
			onEvent?(.skillsChanged)
		case "account/rateLimits/updated":
			onEvent?(.rateLimitsUpdated)
		case "error":
			let error = parameters["error"] as? [String: Any]
			onEvent?(
				.error(
					threadId: threadID,
					turnId: turnID,
					message: error?["message"] as? String ?? "Codex reported an error.",
					willRetry: parameters["willRetry"] as? Bool ?? false
				)
			)
		default:
			break
		}
	}

	private func resolvePendingInteraction(from parameters: [String: Any])
	{
		guard let wireID = parameters["requestId"].flatMap(JSONRPCRequestID.init(json:)),
				let resolvedThreadID = parameters["threadId"] as? String
		else
		{
			return
		}
		let requestID = wireID.key
		if let pendingRequest = interactions[requestID],
			pendingRequest.threadId != resolvedThreadID
		{
			return
		}
		interactions.removeValue(forKey: requestID)
		answeredInteractions.remove(requestID)
		let pendingWrite = pendingInteractionWrites.removeValue(forKey: requestID)
		let generation = connectionGeneration
		// Stop queued responses before an event callback can let the writer advance.
		let writeFailure = pendingWrite?.fail(
			AppServerError.invalidInteraction("This request has already been resolved.")
		)
		onEvent?(.interactionResolved(
			threadId: resolvedThreadID,
			requestID: requestID
		))
		if let writeFailure
		{
			transportWriteFailed(
				writeFailure,
				generation: generation
			)
		}
	}

}
