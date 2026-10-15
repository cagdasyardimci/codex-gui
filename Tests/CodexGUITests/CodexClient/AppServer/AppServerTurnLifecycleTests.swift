import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerTurnLifecycleTests
{
	@Test func imageAndFileContextUseInstalledUserInputShapes() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let startLog = directory.appendingPathComponent("start-context.json")
		let steerLog = directory.appendingPathComponent("steer-context.json")
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    if method == 'initialize':
			        print(json.dumps({'id': message['id'], 'result': {}}), flush=True)
			    elif method == 'turn/start':
			        with open('\(startLog.path)', 'w') as output:
			            json.dump(message, output)
			        print(json.dumps({'id': message['id'], 'result': {'turn': {
			            'id': 'turn-context', 'status': 'inProgress', 'items': []
			        }}}), flush=True)
			    elif method == 'turn/steer':
			        with open('\(steerLog.path)', 'w') as output:
			            json.dump(message, output)
			        print(json.dumps({'id': message['id'], 'result': {
			            'turnId': 'turn-context'
			        }}), flush=True)
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
		try await server.connect()
		let inputs: [TurnInput] = [
			.text("Inspect these"),
			.mention(
				name: "Example.swift",
				path: "/tmp/Example.swift"
			),
			.localImage(path: "/tmp/screenshot.png"),
		]
		_ = try await server.startTurn(
			threadId: "thread-context",
			inputs: inputs,
			model: nil,
			effort: nil,
			skills: []
		)
		_ = try await server.steerTurn(
			threadId: "thread-context",
			expectedTurnId: "turn-context",
			inputs: inputs
		)

		for log in [startLog, steerLog]
		{
			let request = try #require(
				JSONSerialization.jsonObject(with: Data(contentsOf: log)) as? [String: Any]
			)
			let params = try #require(request["params"] as? [String: Any])
			let encoded = try #require(params["input"] as? [[String: Any]])
			#expect(encoded.map
			{
				$0["type"] as? String
			} == ["text", "mention", "localImage"])
			#expect(encoded[0]["text"] as? String == "Inspect these")
			#expect(encoded[1]["name"] as? String == "Example.swift")
			#expect(encoded[1]["path"] as? String == "/tmp/Example.swift")
			#expect(encoded[2]["path"] as? String == "/tmp/screenshot.png")
		}
	}
	@Test func supportedTurnFlowEncodesInteractionResponsesAndStreamsReview() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("interaction-responses.json")
		let executable = try await makeInteractionFlowExecutable(
			in: directory,
			responseLog: responseLog
		)

		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var receivedEvents: [String] = []
		var completedStatus: String?
		var interactionError: String?
		server.onEvent =
		{
			event in
			switch event
			{
			case .turnStarted: receivedEvents.append("turnStarted")
			case .itemStarted: receivedEvents.append("itemStarted")
			case .commandOutputDelta(
				_,
				_,
				_,
				let text
			):
				if text == "hello\n"
				{
					receivedEvents.append("commandOutput")
				}
			case .interaction(let interaction):
				receivedEvents.append("interaction:\(interaction.id)")
				do
				{
					switch interaction.id
					{
					case "integer:100": try server.respond(
							to: interaction.id,
							with: .approval(.accept)
						)
					case "integer:101": try server.respond(
							to: interaction.id,
							with: .approval(.decline)
						)
					case "integer:102":
						try server.respond(
							to: interaction.id,
							with: .approval(.acceptForSession)
						)
					case "integer:103":
						try server.respond(
							to: interaction.id,
							with: .answers(["choice": ["A"]])
						)
					default: interactionError = "Unexpected request \(interaction.id)"
					}
				}
				catch
				{
					interactionError = error.localizedDescription
				}
			case .fileChangeUpdated(
				_,
				_,
				_,
				let changes
			):
				if changes.first?.path == "README.md"
				{
					receivedEvents.append("fileChange")
				}
			case .diffUpdated(
				_,
				_,
				let diff
			):
				if diff.contains("README.md")
				{
					receivedEvents.append("diff")
				}
			case .agentMessageDelta(
				_,
				_,
				_,
				let text
			):
				if text == "Done."
				{
					receivedEvents.append("agentMessage")
				}
			case .turnCompleted(
				_,
				let turn
			):
				completedStatus = turn.status
			default: break
			}
		}

		try await server.connect()
		let models = try await server.models()
		#expect(models.map(\.id) == ["gpt-6-sol"])
		let thread = try await server.startThread(in: directory)
		#expect(thread.summary.id == "thread-1")
		let turn = try await server.startTurn(
			threadId: thread.summary.id,
			text: "Update README"
		)
		#expect(turn.id == "turn-1")

		for _ in 0 ..< 150 where completedStatus == nil
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(completedStatus == "completed")
		#expect(interactionError == nil)
		#expect(receivedEvents.contains("turnStarted"))
		#expect(receivedEvents.contains("itemStarted"))
		#expect(receivedEvents.contains("commandOutput"))
		#expect(receivedEvents.contains("fileChange"))
		#expect(receivedEvents.contains("diff"))
		#expect(receivedEvents.contains("agentMessage"))

		let logData = try Data(contentsOf: responseLog)
		let responseRows = try #require(
			JSONSerialization.jsonObject(with: logData) as? [[String: Any]]
		)
		let results = responseRows.compactMap
		{
			$0["result"] as? [String: Any]
		}
		#expect(results.count == 4)
		#expect(results[0]["decision"] as? String == "accept")
		#expect(results[1]["decision"] as? String == "decline")
		#expect(results[2]["decision"] as? String == "acceptForSession")
		let answers = results[3]["answers"] as? [String: [String: [String]]]
		#expect(answers?["choice"]?["answers"] == ["A"])
	}

	@Test func interruptAcknowledgesOwningTurnBeforeDispatchingCompletion() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let interruptLog = directory.appendingPathComponent("interrupt-request.json")
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    request_id = message.get('id')
			    if method == 'initialize':
			        print(json.dumps({'id': request_id, 'result': {}}), flush=True)
			    elif method == 'turn/start':
			        print(json.dumps({'id': request_id, 'result': {'turn': {
			            'id': 'turn-2', 'status': 'inProgress', 'items': []
			        }}}), flush=True)
			    elif method == 'turn/interrupt':
			        with open('\(interruptLog.path)', 'w') as output:
			            json.dump(message, output)
			        print(json.dumps({'id': request_id, 'result': {}}), flush=True)
			    elif method == 'account/read':
			        # Swift triggers this request only after observing the interrupt acknowledgment.
			        print(json.dumps({'method': 'turn/completed', 'params': {
			            'threadId': 'thread-2',
			            'turn': {'id': 'turn-2', 'status': 'interrupted', 'items': []}
			        }}), flush=True)
			        print(json.dumps({'id': request_id, 'result': {
			            'account': None, 'requiresOpenaiAuth': True
			        }}), flush=True)
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
		var completedStatus: String?
		var completedOwner: (String, String)?
		server.onEvent =
		{
			event in
			if case .turnCompleted(
				let threadId,
				let turn
			) = event
			{
				completedStatus = turn.status
				completedOwner = (threadId, turn.id)
			}
		}
		try await server.connect()
		let turn = try await server.startTurn(
			threadId: "thread-2",
			text: "Long task"
		)
		try await server.interrupt(
			threadId: "thread-2",
			turnId: turn.id
		)
		#expect(completedStatus == nil)
		let request = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: interruptLog)) as? [String: Any]
		)
		#expect(request["method"] as? String == "turn/interrupt")
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["threadId"] as? String == "thread-2")
		#expect(params["turnId"] as? String == turn.id)
		_ = try await server.accountStatus()
		for _ in 0 ..< 100 where completedStatus == nil
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(completedStatus == "interrupted")
		#expect(completedOwner?.0 == "thread-2")
		#expect(completedOwner?.1 == turn.id)
	}
	@Test func steeringAndProgressUseOwningThreadAndActiveTurn() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let requestLog = directory.appendingPathComponent("steering-request.json")
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
			    method = message.get('method')
			    if method == 'initialize':
			        send({'id': message['id'], 'result': {}})
			    elif method == 'turn/steer':
			        with open('\(requestLog.path)', 'w') as output:
			            json.dump(message, output)
			        send({'method': 'turn/plan/updated', 'params': {
			            'threadId': 'thread-running', 'turnId': 'turn-running',
			            'explanation': 'Checking results',
			            'plan': [
			                {'step': 'Inspect', 'status': 'completed'},
			                {'step': 'Verify', 'status': 'inProgress'}
			            ]
			        }})
			        send({'method': 'item/mcpToolCall/progress', 'params': {
			            'threadId': 'thread-running', 'turnId': 'turn-running',
			            'itemId': 'tool-1', 'message': 'Reading records'
			        }})
			        send({'id': message['id'], 'result': {'turnId': 'turn-running'}})
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
		var planUpdates: [TurnPlanUpdate] = []
		var toolProgress: [(String, String, String, String)] = []
		server.onEvent =
		{
			event in
			switch event
			{
			case .planUpdated(let update):
				planUpdates.append(update)
			case .toolProgress(
				let threadId,
				let turnId,
				let itemId,
				let message
			):
				toolProgress.append((threadId, turnId, itemId, message))
			default:
				break
			}
		}
		try await server.connect()

		let acknowledgedTurnID = try await server.steerTurn(
			threadId: "thread-running",
			expectedTurnId: "turn-running",
			text: "Focus on the parser"
		)
		#expect(acknowledgedTurnID == "turn-running")
		#expect(planUpdates.count == 1)
		#expect(planUpdates.first?.threadId == "thread-running")
		#expect(planUpdates.first?.turnId == "turn-running")
		#expect(planUpdates.first?.plan.map(\.status) == [.completed, .inProgress])
		#expect(toolProgress.count == 1)
		#expect(toolProgress.first?.0 == "thread-running")
		#expect(toolProgress.first?.1 == "turn-running")
		#expect(toolProgress.first?.2 == "tool-1")
		#expect(toolProgress.first?.3 == "Reading records")

		let requestData = try Data(contentsOf: requestLog)
		let request = try #require(
			JSONSerialization.jsonObject(with: requestData) as? [String: Any]
		)
		#expect(request["method"] as? String == "turn/steer")
		let parameters = try #require(request["params"] as? [String: Any])
		#expect(parameters["threadId"] as? String == "thread-running")
		#expect(parameters["expectedTurnId"] as? String == "turn-running")
		let input = try #require(parameters["input"] as? [[String: Any]])
		#expect(input.count == 1)
		#expect(input.first?["type"] as? String == "text")
		#expect(input.first?["text"] as? String == "Focus on the parser")
		#expect((input.first?["text_elements"] as? [Any])?.isEmpty == true)
	}
	private func makeInteractionFlowExecutable(
		in directory: URL,
		responseLog: URL
	) async throws -> URL
	{
		return try await AppServerTestExecutable.mockExecutable(
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

			def request(request_id, method, params):
			    send({'id': request_id, 'method': method, 'params': params})

			def approval(request_id, method):
			    request(request_id, method, {
			        'threadId': 'thread-1', 'turnId': 'turn-1', 'itemId': 'command-1',
			        'reason': 'Mock approval', 'command': 'echo hello', 'cwd': '/tmp'
			    })

			responses = []
			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    request_id = message.get('id')
			    if method == 'initialize':
			        send({'id': request_id, 'result': {'userAgent': 'mock'}})
			    elif method == 'model/list':
			        send({'id': request_id, 'result': {'data': [{
			            'model': 'gpt-6-sol', 'displayName': 'GPT-6 Sol',
			            'supportedReasoningEfforts': [{'reasoningEffort': 'high'}],
			            'defaultReasoningEffort': 'high', 'isDefault': True
			        }], 'nextCursor': None}})
			    elif method == 'thread/start':
			        if message['params'].get('ephemeral'):
			            send({'id': request_id, 'error': {'code': -32000,
			                  'message': 'Title generation unavailable in interaction fixture'}})
			            continue
			        send({'id': request_id, 'result': {'thread': {
			            'id': 'thread-1', 'preview': '', 'cwd': message['params']['cwd'],
			            'status': {'type': 'idle'}
			        }, 'cwd': message['params']['cwd']}})
			    elif method == 'turn/start':
			        turn = {'id': 'turn-1', 'status': 'inProgress', 'items': []}
			        send({'id': request_id, 'result': {'turn': turn}})
			        send({'method': 'turn/started', 'params': {
			            'threadId': 'thread-1', 'turn': turn
			        }})
			        send({'method': 'item/started', 'params': {
			            'threadId': 'thread-1', 'turnId': 'turn-1',
			            'item': {'id': 'command-1', 'type': 'commandExecution',
			                     'command': 'echo hello', 'cwd': '/tmp', 'status': 'inProgress'}
			        }})
			        send({'method': 'item/commandExecution/outputDelta', 'params': {
			            'threadId': 'thread-1', 'turnId': 'turn-1',
			            'itemId': 'command-1', 'delta': 'hello\\n'
			        }})
			        approval(100, 'item/commandExecution/requestApproval')
			    elif request_id in (100, 101, 102, 103) and method is None:
			        responses.append(message)
			        send({'method': 'serverRequest/resolved', 'params': {
			            'threadId': 'thread-1', 'requestId': request_id
			        }})
			        if request_id == 100:
			            approval(101, 'item/commandExecution/requestApproval')
			        elif request_id == 101:
			            approval(102, 'item/fileChange/requestApproval')
			        elif request_id == 102:
			            request(103, 'item/tool/requestUserInput', {
			                'threadId': 'thread-1', 'turnId': 'turn-1', 'itemId': 'question-1',
			                'isBlocking': True, 'autoResolutionMs': None,
			                'questions': [{
			                    'id': 'choice', 'header': 'Choice', 'question': 'Which option?',
			                    'isOther': False, 'isSecret': False,
			                    'options': [{'label': 'A', 'description': 'Option A'}]
			                }]
			            })
			        elif request_id == 103:
			            with open('\(responseLog.path)', 'w') as output:
			                json.dump(responses, output)
			            change = {'path': 'README.md', 'kind': 'update',
			                      'diff': '@@ -1 +1 @@\\n-old\\n+new\\n'}
			            send({'method': 'item/fileChange/patchUpdated', 'params': {
			                'threadId': 'thread-1', 'turnId': 'turn-1',
			                'itemId': 'change-1', 'changes': [change]
			            }})
			            send({'method': 'turn/diff/updated', 'params': {
			                'threadId': 'thread-1', 'turnId': 'turn-1',
			                'diff': 'diff --git a/README.md b/README.md\\n'
			            }})
			            send({'method': 'item/completed', 'params': {
			                'threadId': 'thread-1', 'turnId': 'turn-1',
			                'item': {'id': 'change-1', 'type': 'fileChange',
			                         'status': 'completed', 'changes': [change]}
			            }})
			            send({'method': 'item/agentMessage/delta', 'params': {
			                'threadId': 'thread-1', 'turnId': 'turn-1',
			                'itemId': 'message-1', 'delta': 'Done.'
			            }})
			            send({'method': 'turn/completed', 'params': {
			                'threadId': 'thread-1',
			                'turn': {'id': 'turn-1', 'status': 'completed', 'items': []}
			            }})
			"""
		)
	}
}
