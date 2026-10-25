import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerApprovalRoutingTests
{
	@Test func permissionAndStructuredApprovalResponsesKeepRequestIDsAndScopes() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("responses.json")
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			def send(message):
			    print(json.dumps(message), flush=True)

			responses = []
			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    request_id = message.get('id')
			    if method == 'initialize':
			        send({'id': request_id, 'result': {}})
			    elif method == 'turn/start':
			        send({'id': request_id, 'result': {'turn': {
			            'id': 'turn-1', 'status': 'inProgress', 'items': []
			        }}})
			        for approval_id in (201, 202):
			            send({'id': approval_id, 'method': 'item/permissions/requestApproval',
			                  'params': {
			                      'threadId': 'thread-1', 'turnId': 'turn-1',
			                      'itemId': 'permission-' + str(approval_id), 'cwd': '/tmp',
			                      'startedAtMs': 1,
			                      'permissions': {'fileSystem': {
			                          'write': ['/tmp/output', '/tmp/log']}}
			                  }})
			        send({'id': 203, 'method': 'item/commandExecution/requestApproval',
			              'params': {
			                  'threadId': 'thread-1', 'turnId': 'turn-1',
			                  'itemId': 'command-1', 'startedAtMs': 1,
			                  'availableDecisions': [
			                      'decline',
			                      {'acceptWithExecpolicyAmendment': {
			                          'execpolicy_amendment': ['git', 'status']}}
			                  ]
			              }})
			    elif request_id in (201, 202, 203) and method is None:
			        responses.append(message)
			        if len(responses) == 3:
			            with open('\(responseLog.path)', 'w') as output:
			                json.dump(responses, output)
			"""
		)

		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var interactions: [String: PendingInteraction] = [:]
		var responseError: String?
		server.onEvent =
		{
			event in
			guard case .interaction(let interaction) = event
			else
			{
				return
			}
			interactions[interaction.id] = interaction
			guard interactions.count == 3
			else
			{
				return
			}
			do
			{
				let denied = try #require(interactions["integer:202"])
				let command = try #require(interactions["integer:203"])
				let granted = try #require(interactions["integer:201"])
				try server.respond(
					to: denied.id,
					with: .permissions(
						granted: [:],
						scope: .turn
					)
				)
				do
				{
					try server.respond(
						to: granted.id,
						with: .permissions(
							granted: ["fileSystem": ["write": ["/tmp/unrequested"]]],
							scope: .session
						)
					)
					responseError = "Access outside the request was granted"
				}
				catch
				{
				}
				do
				{
					try server.respond(
						to: command.id,
						with: .approval(.accept)
					)
					responseError = "A decision outside availableDecisions was accepted"
				}
				catch
				{
				}
				try server.respond(
					to: command.id,
					with: .approval(.acceptWithExecpolicyAmendment([
						"git",
						"status"
					]))
				)
				try server.respond(
					to: granted.id,
					with: .permissions(
						granted: ["fileSystem": ["write": ["/tmp/output"]]],
						scope: .session
					)
				)
			}
			catch
			{
				responseError = error.localizedDescription
			}
		}

		try await server.connect()
		_ = try await server.startTurn(
			threadId: "thread-1",
			text: "Test permissions"
		)
		for _ in 0 ..< 150 where !FileManager.default.fileExists(atPath: responseLog.path)
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(responseError == nil)
		#expect(
			interactions["integer:203"]?.availableDecisions == [
				.decline,
				.acceptWithExecpolicyAmendment(["git", "status"]),
			]
		)
		let logData = try Data(contentsOf: responseLog)
		let responses = try #require(
			JSONSerialization.jsonObject(with: logData) as? [[String: Any]]
		)
		#expect(responses.compactMap
		{
			$0["id"] as? Int
		} == [202, 203, 201])
		let denied = responses[0]["result"] as? [String: Any]
		#expect((denied?["permissions"] as? [String: Any])?.isEmpty == true)
		#expect(denied?["scope"] as? String == "turn")
		let command = responses[1]["result"] as? [String: Any]
		let decision = command?["decision"] as? [String: [String: [String]]]
		#expect(
			decision?["acceptWithExecpolicyAmendment"]?["execpolicy_amendment"] == [
				"git",
				"status",
			]
		)
		let granted = responses[2]["result"] as? [String: Any]
		#expect(granted?["scope"] as? String == "session")
		let permissions = granted?["permissions"] as? [String: [String: [String]]]
		#expect(permissions?["fileSystem"]?["write"] == ["/tmp/output"])
	}

	@Test func serverRequestIDMayMatchOutstandingClientRequestID() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("colliding-response.json")
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			def send(message):
			    print(json.dumps(message), flush=True)

			for line in sys.stdin:
			    message = json.loads(line)
			    if message.get('method') == 'initialize':
			        send({'id': message['id'],
			              'method': 'item/permissions/requestApproval',
			              'params': {
			                  'threadId': 'thread-1', 'turnId': 'turn-1',
			                  'itemId': 'permission-1', 'cwd': '/tmp',
			                  'startedAtMs': 1,
			                  'permissions': {'network': {'enabled': True}}
			              }})
			    elif message.get('id') == 1 and message.get('method') is None:
			        with open('\(responseLog.path)', 'w') as output:
			            json.dump(message, output)
			        send({'id': 1, 'result': {'userAgent': 'mock'}})
			"""
		)

		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var receivedInteraction = false
		server.onEvent =
		{
			event in
			guard case .interaction(let interaction) = event
			else
			{
				return
			}
			receivedInteraction = true
			try? server.respond(
				to: interaction.id,
				with: .permissions(
					granted: [:],
					scope: .turn
				)
			)
		}
		try await server.connect()
		#expect(receivedInteraction)
		let logData = try Data(contentsOf: responseLog)
		let response = try #require(
			JSONSerialization.jsonObject(with: logData) as? [String: Any]
		)
		#expect(response["id"] as? Int == 1)
		let result = response["result"] as? [String: Any]
		#expect((result?["permissions"] as? [String: Any])?.isEmpty == true)
	}

}
