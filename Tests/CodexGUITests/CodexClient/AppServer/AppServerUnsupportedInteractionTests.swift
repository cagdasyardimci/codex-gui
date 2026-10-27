import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppServerUnsupportedInteractionTests
{
	@Test(
		arguments: [
			"mcpServer/elicitation/request",
			"execCommandApproval",
			"applyPatchApproval",
			"item/tool/futureInteractiveRequest",
		],
		[false, true]
	)
	func unsupportedRequestsReplyAndReportTheirOwner(
		method: String,
		usesStringID: Bool
	) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("unsupported-response.json")
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
		#!/usr/bin/env python3
		import json
		import sys

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		interaction_id = 'request-42' if \(usesStringID ? "True" : "False") else 42
		pending_client_id = None
		def send(message):
		    print(json.dumps(message), flush=True)

		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    if method == 'initialize':
		        send({'id': message['id'], 'result': {}})
		    elif method == 'fixture/unsupported':
		        pending_client_id = message['id']
		        send({'id': interaction_id, 'method': '\(method)', 'params': {
		            'threadId': 'owning-thread', 'turnId': 'owning-turn',
		            'itemId': 'unsupported-item'
		        }})
		    elif method is None and pending_client_id is not None:
		        with open('\(responseLog.path)', 'w') as output:
		            json.dump(message, output)
		        # Acknowledge only after the actual client response reaches the subprocess.
		        send({'id': pending_client_id, 'result': {'resolved': True}})
		        pending_client_id = None
		"""
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.onEvent = nil
			server.disconnect()
		}
		var feedbackOwners: [String] = []
		var feedbackTurns: [String] = []
		var feedbackMessages: [String] = []
		var feedbackRetries: [Bool] = []
		var interactionCount = 0
		server.onEvent =
		{
			event in
			switch event
			{
			case .error(
				let threadID,
				let turnID,
				let message,
				let willRetry
			):
				feedbackOwners.append(threadID)
				feedbackTurns.append(turnID)
				feedbackMessages.append(message)
				feedbackRetries.append(willRetry)
			case .interaction: interactionCount += 1
			default: break
			}
		}
		try await server.connect()
		let acknowledgement = try await server.request(
			"fixture/unsupported",
			params: [:]
		)
		#expect(acknowledgement["resolved"] as? Bool == true)
		#expect(feedbackOwners == ["owning-thread"])
		#expect(feedbackTurns == ["owning-turn"])
		#expect(feedbackRetries == [false])
		#expect(interactionCount == 0)
		#expect(server.interactions.isEmpty)
		#expect(server.pendingInteractionWrites.isEmpty)
		#expect(server.answeredInteractions.isEmpty)
		let response = try #require(JSONSerialization.jsonObject(
			with: Data(contentsOf: responseLog)
		) as? [String: Any])
		if usesStringID
		{
			#expect(response["id"] as? String == "request-42")
		}
		else
		{
			#expect(response["id"] as? Int == 42)
		}
		switch method
		{
		case "mcpServer/elicitation/request":
			#expect(Set(response.keys) == ["id", "result"])
			let result = try #require(response["result"] as? [String: Any])
			#expect(Set(result.keys) == ["action", "content", "_meta"])
			#expect(result["action"] as? String == "decline")
			#expect(result["content"] is NSNull)
			#expect(result["_meta"] is NSNull)
			#expect(feedbackMessages == [
				"MCP form request declined."
			])
		case "execCommandApproval", "applyPatchApproval":
			#expect(Set(response.keys) == ["id", "result"])
			#expect(response["result"] as? [String: String] == ["decision": "abort"])
			#expect(feedbackMessages == [
				"Codex sent an older approval format. The request was cancelled."
			])
		default:
			#expect(Set(response.keys) == ["id", "error"])
			let error = try #require(response["error"] as? [String: Any])
			#expect(Set(error.keys) == ["code", "message"])
			#expect(error["code"] as? Int == -32601)
			#expect(error["message"] as? String == "Unsupported by this client")
			#expect(feedbackMessages == [
				"Request declined: item/tool/futureInteractiveRequest."
			])
		}
	}
}
