import Foundation

// Owns server request decoding and validation of interaction responses.
extension AppServer
{
	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
		guard let pendingRequest = interactions[requestID],
				!answeredInteractions.contains(requestID)
		else
		{
			throw AppServerError.invalidInteraction("This request has already been resolved.")
		}
		let result = try validatedInteractionResult(
			for: response,
			kind: pendingRequest.kind,
			availableDecisions: pendingRequest.decisions,
			requestedPermissions: pendingRequest.permissions
		)
		try send(["id": pendingRequest.id.wireValue, "result": result])
		answeredInteractions.insert(requestID)
	}

	private func validatedInteractionResult(
		for response: InteractionResponse,
		kind: InteractionKind,
		availableDecisions: [ApprovalDecision]?,
		requestedPermissions: [String: Any]?
	) throws -> [String: Any]
	{
		let result: [String: Any]
		switch (kind, response)
		{
		case (.commandApproval, .approval(let decision)),
				(.fileChangeApproval, .approval(let decision)):
			if let decisions = availableDecisions, !decisions.contains(decision)
			{
				throw AppServerError.invalidInteraction("Codex did not offer that decision.")
			}
			result = ["decision": decision.wireValue]
		case (.question, .answers(let answers)):
			result = ["answers": answers.mapValues
			{
				["answers": $0]
			}]
		case (.permissionApproval, .permissions(
			let granted,
			let scope
		)):
			if !Self.isGrantedSubset(
				granted,
				of: requestedPermissions ?? [:]
			)
			{
				throw AppServerError.invalidInteraction("The granted access exceeds the request.")
			}
			result = ["permissions": granted, "scope": scope.rawValue]
		default:
			throw AppServerError.invalidInteraction("The response does not match the request type.")
		}
		return result
	}

	func receiveServerRequest(
		id: Any,
		method: String,
		parameters: [String: Any]
	)
	{
		if method == "mcpServer/elicitation/request"
		{
			declineUnsupportedMCPForm(
				id: id,
				parameters: parameters
			)
			return
		}
		let usesLegacyApprovalFormat =
			method == "applyPatchApproval" || method == "execCommandApproval"
		if usesLegacyApprovalFormat
		{
			cancelLegacyApproval(
				id: id,
				parameters: parameters
			)
			return
		}
		guard let wireID = JSONRPCRequestID(json: id)
		else
		{
			reportInvalidMessage(for: connectionGeneration)
			return
		}
		let requestID = wireID.key
		guard interactions[requestID] == nil
		else
		{
			reportInvalidMessage(for: connectionGeneration)
			return
		}
		let kind: InteractionKind
		switch method
		{
		case "item/commandExecution/requestApproval": kind = .commandApproval
		case "item/fileChange/requestApproval": kind = .fileChangeApproval
		case "item/permissions/requestApproval": kind = .permissionApproval
		case "item/tool/requestUserInput": kind = .question
		default: kind = .unsupported(method)
		}
		if case .unsupported = kind
		{
			rejectUnsupportedInteraction(
				id: id,
				method: method,
				parameters: parameters
			)
			return
		}
		registerAndPublishInteraction(
			id: wireID,
			kind: kind,
			parameters: parameters
		)
	}

	private func registerAndPublishInteraction(
		id wireID: JSONRPCRequestID,
		kind: InteractionKind,
		parameters: [String: Any]
	)
	{
		let requestID = wireID.key
		let availableDecisions = (parameters["availableDecisions"] as? [Any])?
			.compactMap(ApprovalDecision.init(json:))
		let threadID = parameters["threadId"] as? String ?? ""
		interactions[requestID] = (
			wireID,
			threadID,
			kind,
			availableDecisions,
			parameters["permissions"] as? [String: Any]
		)
		let network = parameters["networkApprovalContext"] as? [String: Any]
		let questionPayloads = parameters["questions"] as? [[String: Any]] ?? []
		let questions = questionPayloads.compactMap(InteractionQuestion.init(json:))
		onEvent?(
			.interaction(
				PendingInteraction(
					id: requestID,
					threadId: parameters["threadId"] as? String ?? "",
					turnId: parameters["turnId"] as? String ?? "",
					itemId: parameters["itemId"] as? String ?? "",
					approvalId: parameters["approvalId"] as? String,
					kind: kind,
					reason: parameters["reason"] as? String,
					command: parameters["command"] as? String,
					cwd: parameters["cwd"] as? String,
					grantRoot: parameters["grantRoot"] as? String,
					networkHost: network?["host"] as? String,
					networkProtocol: network?["protocol"] as? String,
					questions: questions,
					requestedPermissions: parameters["permissions"] as? [String: Any],
					additionalPermissions: parameters["additionalPermissions"] as? [String: Any],
					availableDecisions: availableDecisions
				)
			)
		)
	}

	private func declineUnsupportedMCPForm(
		id: Any,
		parameters: [String: Any]
	)
	{
		onEvent?(
			.error(
				threadId: parameters["threadId"] as? String ?? "",
				turnId: parameters["turnId"] as? String ?? "",
				message:
				"This version of Codex GUI cannot display MCP forms. The request was "
					+ "declined.",
				willRetry: false
			)
		)
		try? send([
			"id": id,
			"result": [
				"action": "decline",
				"content": NSNull(),
				"_meta": NSNull(),
			],
		])
	}

	private func cancelLegacyApproval(
		id: Any,
		parameters: [String: Any]
	)
	{
		onEvent?(
			.error(
				threadId: parameters["threadId"] as? String ?? "",
				turnId: parameters["turnId"] as? String ?? "",
				message: "Codex sent an older approval format. The request was cancelled.",
				willRetry: false
			)
		)
		try? send(["id": id, "result": ["decision": "abort"]])
	}

	private func rejectUnsupportedInteraction(
		id: Any,
		method: String,
		parameters: [String: Any]
	)
	{
		onEvent?(
			.error(
				threadId: parameters["threadId"] as? String ?? "",
				turnId: parameters["turnId"] as? String ?? "",
				message: "This version of Codex GUI cannot handle \(method).",
				willRetry: false
			)
		)
		try? send([
			"id": id,
			"error": ["code": -32601, "message": "Unsupported by this client"]
		])
	}

	private static func isGrantedSubset(
		_ granted: Any,
		of requested: Any
	) -> Bool
	{
		if let granted = granted as? [String: Any], let requested = requested as? [String: Any]
		{
			return granted.allSatisfy
			{
				key, value in
				guard let requestedValue = requested[key]
				else
				{
					return false
				}
				return isGrantedSubset(
					value,
					of: requestedValue
				)
			}
		}
		if let granted = granted as? [Any], let requested = requested as? [Any]
		{
			return granted.allSatisfy
			{
				value in requested.contains
				{
					sameJSON(
						value,
						$0
					)
				}
			}
		}
		return sameJSON(
			granted,
			requested
		)
	}

	private static func sameJSON(
		_ first: Any,
		_ second: Any
	) -> Bool
	{
		guard
			let firstData = try? JSONSerialization.data(
				withJSONObject: ["value": first],
				options: [.sortedKeys]
			),
			let secondData = try? JSONSerialization.data(
				withJSONObject: ["value": second],
				options: [.sortedKeys]
			)
		else
		{
			return false
		}
		return firstData == secondData
	}
}
