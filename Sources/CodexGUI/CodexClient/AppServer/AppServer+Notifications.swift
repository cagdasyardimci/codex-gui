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
		let turnID = parameters["turnId"] as? String ?? ""
		switch method
		{
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
			onEvent?(.interactionResolved(
				threadId: resolvedThreadID,
				requestID: requestID
			))
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
}
