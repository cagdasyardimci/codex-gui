import Foundation

extension AppServer
{
	func steerQueuedInput(
		threadID: String,
		expectedTurnID: String,
		inputJSON: Data
	) async throws -> String
	{
		let result = try await request(
			"turn/steer",
			params: [
				"threadId": threadID,
				"expectedTurnId": expectedTurnID,
				"input": JSONSerialization.jsonObject(with: inputJSON)
			]
		)
		guard let turnID = result["turnId"] as? String, turnID == expectedTurnID
		else
		{
			throw AppServerError
				.protocolError("Codex returned an unexpected turn ID for steering.")
		}
		return turnID
	}

	var canProbeThreadQueue: Bool
	{
		true
	}

	func threadQueuePage(
		threadID: String,
		cursor: String?,
		limit: Int?
	) async throws -> ThreadQueuePage
	{
		var parameters: [String: Any] = ["threadId": threadID]
		if let cursor
		{
			parameters["cursor"] = cursor
		}
		if let limit
		{
			parameters["limit"] = limit
		}
		let response: [String: Any]
		do
		{
			response = try await request(
				"thread/queue/list",
				params: parameters
			)
		}
		catch AppServerError.requestRejected(let message)
		{
			let lower = message.lowercased()
			if lower.contains("method not found") || lower.contains("unknown variant") || lower
				.contains("unknown method")
			{
				throw ThreadQueueUnsupported()
			}
			throw AppServerError.requestRejected(message)
		}
		guard let data = response["data"] as? [[String: Any]],
				response["nextCursor"] is NSNull || response["nextCursor"] is String
		else
		{
			throw AppServerError.protocolError("Invalid queue page.")
		}
		return ThreadQueuePage(
			data: try data.map(ThreadQueuedSubmission.init(json:)),
			nextCursor: response["nextCursor"] as? String
		)
	}

	func addThreadQueue(
		threadID: String,
		inputJSON: Data,
		clientUserMessageID: String
	) async throws -> ThreadQueuedSubmission
	{
		let result = try await request(
			"thread/queue/add",
			params: [
				"threadId": threadID,
				"input": JSONSerialization.jsonObject(with: inputJSON),
				"clientUserMessageId": clientUserMessageID
			]
		)
		guard let value = result["queuedSubmission"] as? [String: Any]
		else
		{
			throw AppServerError.protocolError("Missing queued submission.")
		}
		let submission = try ThreadQueuedSubmission(json: value)
		guard submission.clientUserMessageID == clientUserMessageID
		else
		{
			throw AppServerError.protocolError("Queued submission identity changed.")
		}
		return submission
	}

	func updateThreadQueue(
		threadID: String,
		queuedSubmissionID: String,
		inputJSON: Data
	) async throws -> ThreadQueuedSubmission
	{
		let result = try await request(
			"thread/queue/update",
			params: [
				"threadId": threadID,
				"queuedSubmissionId": queuedSubmissionID,
				"input": JSONSerialization.jsonObject(with: inputJSON)
			]
		)
		guard let value = result["queuedSubmission"] as? [String: Any]
		else
		{
			throw AppServerError.protocolError("Missing updated queued submission.")
		}
		let submission = try ThreadQueuedSubmission(json: value)
		guard submission.id == queuedSubmissionID
		else
		{
			throw AppServerError.protocolError("Queued submission identity changed.")
		}
		return submission
	}

	func deleteThreadQueue(
		threadID: String,
		queuedSubmissionID: String
	) async throws -> Bool
	{
		let result = try await request(
			"thread/queue/delete",
			params: ["threadId": threadID, "queuedSubmissionId": queuedSubmissionID]
		)
		guard let deleted = result["deleted"] as? Bool
		else
		{
			throw AppServerError.protocolError("Missing queue deletion result.")
		}
		return deleted
	}

	func reorderThreadQueue(
		threadID: String,
		queuedSubmissionIDs: [String]
	) async throws
	{
		_ = try await request(
			"thread/queue/reorder",
			params: ["threadId": threadID, "queuedSubmissionIds": queuedSubmissionIDs]
		)
	}

	func startThreadQueue(
		threadID: String,
		queuedSubmissionID: String?
	) async throws -> CodexTurn
	{
		var parameters: [String: Any] = ["threadId": threadID]
		if let queuedSubmissionID
		{
			parameters["queuedSubmissionId"] = queuedSubmissionID
		}
		let result = try await request(
			"thread/queue/start",
			params: parameters
		)
		guard let raw = result["turn"] as? [String: Any],
				let turn = CodexTurn(json: raw)
		else
		{
			throw AppServerError.protocolError("Missing queued turn.")
		}
		return turn
	}
}
