import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerIntegrationTests
{
	@Test func imageAndFileContextUseInstalledUserInputShapes() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let startLog = directory.appendingPathComponent("start-context.json")
		let steerLog = directory.appendingPathComponent("steer-context.json")
		let executable = try mockExecutable(
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

	@Test func stalledVersionCheckTimesOutWithoutBlockingMainActor() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import signal
			import time

			signal.signal(signal.SIGTERM, signal.SIG_IGN)
			time.sleep(8)
			"""
		)
		let server = AppServer(
			executableOverride: executable,
			versionCheckTimeout: .seconds(3)
		)
		let clock = ContinuousClock()
		let startedAt = clock.now
		let versionTask = Task
		{
			try await server.executableVersion()
		}
		let mainActorProgressTask = Task
		{
			@MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			return clock.now
		}
		let mainActorProgressTime = await mainActorProgressTask.value
		// A synchronous probe would hold the main actor through the 3-second deadline.
		// Leave room for scheduling delays when other test suites run in parallel.
		#expect(startedAt.duration(to: mainActorProgressTime) < .seconds(2.5))

		var versionError: AppServerError?
		do
		{
			_ = try await versionTask.value
		}
		catch let error as AppServerError
		{
			versionError = error
		}
		#expect(versionError != nil)
		if case .some(.requestTimedOut("--version")) = versionError
		{
			#expect(true)
		}
		else
		{
			#expect(
				Bool(false),
				"Expected the version probe to time out"
			)
		}
		// Timeout cleanup can wait up to 1.25 seconds before killing the child.
		// This bound still finishes before the 8-second fixture could exit on its own.
		#expect(startedAt.duration(to: clock.now) < .seconds(6))
	}

	@Test func continuousVersionOutputCannotStarveProbeDeadline() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import signal
			import sys
			import time

			signal.signal(signal.SIGTERM, signal.SIG_IGN)
			deadline = time.monotonic() + 8
			while time.monotonic() < deadline:
			    sys.stdout.write('x' * 1024)
			    sys.stdout.flush()
			"""
		)
		let server = AppServer(
			executableOverride: executable,
			versionCheckTimeout: .seconds(3)
		)
		let clock = ContinuousClock()
		let startedAt = clock.now
		let versionTask = Task
		{
			try await server.executableVersion()
		}
		let mainActorProgressTask = Task
		{
			@MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			return clock.now
		}
		let mainActorProgressTime = await mainActorProgressTask.value
		#expect(startedAt.duration(to: mainActorProgressTime) < .seconds(2.5))

		var versionError: AppServerError?
		do
		{
			_ = try await versionTask.value
		}
		catch let error as AppServerError
		{
			versionError = error
		}
		if case .some(.requestTimedOut("--version")) = versionError
		{
			#expect(true)
		}
		else
		{
			#expect(
				Bool(false),
				"Expected the continuous-output version probe to time out"
			)
		}
		#expect(startedAt.duration(to: clock.now) < .seconds(6))
	}

	@Test func supportedTurnFlowEncodesInteractionResponsesAndStreamsReview() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("interaction-responses.json")
		let executable = try makeInteractionFlowExecutable(
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
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let interruptLog = directory.appendingPathComponent("interrupt-request.json")
		let executable = try mockExecutable(
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

	@Test func permissionAndStructuredApprovalResponsesKeepRequestIDsAndScopes() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("responses.json")
		let executable = try mockExecutable(
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
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("colliding-response.json")
		let executable = try mockExecutable(
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

	@Test func interleavedApprovalsKeepRequestIDTypeCallbackAndThread() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let responseLog = directory.appendingPathComponent("interleaved-responses.json")
		let executable = try mockExecutable(
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
			        thread_id = message['params']['threadId']
			        turn_id = 'turn-' + thread_id
			        send({'id': request_id, 'result': {'turn': {
			            'id': turn_id, 'status': 'inProgress', 'items': []
			        }}})
			        send({'method': 'turn/started', 'params': {
			            'threadId': thread_id, 'turn': {
			                'id': turn_id, 'status': 'inProgress', 'items': []
			            }
			        }})
			        approval_id = 13 if thread_id == 'alpha' else '13'
			        send({'id': approval_id, 'method': 'item/commandExecution/requestApproval',
			              'params': {
			                  'threadId': thread_id, 'turnId': turn_id,
			                  'itemId': 'shared-command', 'approvalId': 'callback-' + thread_id,
			                  'startedAtMs': 1, 'command': 'printf synthetic'
			              }})
			        if thread_id == 'beta':
			            send({'method': 'serverRequest/resolved', 'params': {
			                'threadId': 'alpha', 'requestId': '13'
			            }})
			    elif method is None and request_id in (13, '13'):
			        responses.append(message)
			        thread_id = 'alpha' if isinstance(request_id, int) else 'beta'
			        send({'method': 'serverRequest/resolved', 'params': {
			            'threadId': thread_id, 'requestId': request_id
			        }})
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
		var resolutions: [(String, String)] = []
		var startedThreads: [String] = []
		server.onEvent =
		{
			event in
			switch event
			{
			case .turnStarted(
				let threadID,
				_
			): startedThreads.append(threadID)
			case .interaction(let interaction): interactions[interaction.id] = interaction
			case .interactionResolved(
				let threadID,
				let requestID
			):
				resolutions.append((threadID, requestID))
			default: break
			}
		}
		try await server.connect()
		_ = try await server.startTurn(
			threadId: "alpha",
			text: "First synthetic task"
		)
		_ = try await server.startTurn(
			threadId: "beta",
			text: "Second synthetic task"
		)
		for _ in 0 ..< 100 where interactions.count < 2
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(Set(startedThreads) == ["alpha", "beta"])
		let integer = try #require(interactions["integer:13"])
		let string = try #require(interactions["string:13"])
		#expect(integer.threadId == "alpha" && integer.turnId == "turn-alpha")
		#expect(string.threadId == "beta" && string.turnId == "turn-beta")
		#expect(integer.itemId == string.itemId)
		#expect(integer.approvalId == "callback-alpha")
		#expect(string.approvalId == "callback-beta")
		#expect(resolutions.isEmpty)

		try server.respond(
			to: string.id,
			with: .approval(.decline)
		)
		try server.respond(
			to: integer.id,
			with: .approval(.accept)
		)
		for _ in 0 ..< 100 where resolutions.count < 2
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(resolutions.map
		{
			"\($0.0):\($0.1)"
		} == ["beta:string:13", "alpha:integer:13"])
		let responses = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: responseLog)) as? [[String: Any]]
		)
		#expect(responses[0]["id"] as? String == "13")
		#expect(responses[1]["id"] as? Int == 13)
	}

	@Test func checkoutCwdIsCheckedOnStartResumeListAndTurnOverride() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let alpha = directory.appendingPathComponent(
			"alpha",
			isDirectory: true
		)
		let beta = directory.appendingPathComponent(
			"beta",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: alpha,
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: beta,
			withIntermediateDirectories: true
		)
		let alphaAlias = directory.appendingPathComponent(
			"alpha-alias",
			isDirectory: true
		)
		try FileManager.default.createSymbolicLink(
			at: alphaAlias,
			withDestinationURL: alpha
		)
		let requestLog = directory.appendingPathComponent("cwd-requests.json")
		let responseMode = directory.appendingPathComponent("cwd-response-mode")
		let executable = try makeCheckoutValidationExecutable(
			in: directory,
			requestLog: requestLog,
			responseMode: responseMode
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
		let first = try await server.startThread(in: alpha)
		let second = try await server.startThread(in: beta)
		#expect(first.summary.id != second.summary.id)
		#expect(try await server.threads(for: alpha).map(\.id) == [first.summary.id])
		#expect(try await server.threads(for: beta).map(\.id) == [second.summary.id])
		#expect(
			try await server.resumeThread(
				id: first.summary.id,
				expectedDirectory: alpha
			).summary
				.cwd
				== alpha.standardizedFileURL.path
		)
		#expect(
			try await server.resumeThread(
				id: first.summary.id,
				expectedDirectory: alphaAlias
			)
			.summary.cwd
			== alpha.standardizedFileURL.path
		)
		do
		{
			_ = try await server.resumeThread(
				id: first.summary.id,
				expectedDirectory: beta
			)
			Issue.record("A conversation from alpha was allowed in beta")
		}
		catch let error as AppServerError
		{
			if case .protocolError = error
			{
			}
			else
			{
				Issue.record("Unexpected resume error: \(error)")
			}
		}
		for mode in ["start-summary", "start-result", "list"]
		{
			try mode.write(
				to: responseMode,
				atomically: true,
				encoding: .utf8
			)
			do
			{
				if mode == "list"
				{
					_ = try await server.threads(for: alpha)
				}
				else
				{
					_ = try await server.startThread(in: alpha)
				}
				Issue.record("Accepted a mismatched checkout response for \(mode)")
			}
			catch AppServerError.protocolError
			{
				// The reply is valid JSON with a deliberately mismatched checkout identity.
			}
		}
		try FileManager.default.removeItem(at: responseMode)
		_ = try await server.startTurn(
			threadId: second.summary.id,
			text: "Synthetic task",
			model: nil,
			effort: nil,
			skills: [],
			cwd: beta
		)
		let requests = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: requestLog)) as? [[String: Any]]
		)
		let resumeRequests = requests.filter
		{
			$0["method"] as? String == "thread/resume"
		}
		#expect(resumeRequests.count == 3)
		#expect(
			resumeRequests.allSatisfy
			{
				($0["params"] as? [String: Any])?["cwd"] == nil
			}
		)
		let turnRequest = try #require(requests.last
		{
			$0["method"] as? String == "turn/start"
		})
		#expect(
			(turnRequest["params"] as? [String: Any])?["cwd"] as? String
				== beta.standardizedFileURL.path
		)
	}

	@Test func conversationListingAndManagementUsePaginatedAppServerMethods() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let requestLog = directory.appendingPathComponent("requests.json")
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			requests = []
			def send(message):
			    print(json.dumps(message), flush=True)

			def record(message):
			    requests.append(message)
			    with open('\(requestLog.path)', 'w') as output:
			        json.dump(requests, output)

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    request_id = message.get('id')
			    params = message.get('params', {})
			    if method == 'initialize':
			        send({'id': request_id, 'result': {}})
			    elif method == 'thread/list':
			        record(message)
			        archived = params['archived']
			        cursor = params.get('cursor')
			        if cursor is None:
			            token = 'archived-page-two' if archived else 'active-page-two'
			            thread_id = 'archived-first' if archived else 'active-first'
			            result = {'data': [{
			                'id': thread_id, 'name': thread_id, 'preview': 'first page',
			                'cwd': params['cwd'], 'status': {'type': 'idle'}
			            }], 'nextCursor': token}
			        else:
			            thread_id = 'archived-second' if archived else 'active-second'
			            result = {'data': [{
			                'id': thread_id, 'name': thread_id, 'preview': 'second page',
			                'cwd': params['cwd'], 'status': {'type': 'idle'}
			            }], 'nextCursor': None}
			        send({'id': request_id, 'result': result})
			    elif method in ('thread/name/set', 'thread/archive',
			                    'thread/unarchive', 'thread/delete'):
			        record(message)
			        result = {}
			        if method == 'thread/unarchive':
			            result = {'thread': {
			                'id': params['threadId'],
			                'name': 'Restored title', 'preview': 'restored',
			                'cwd': '/tmp', 'status': {'type': 'idle'}
			            }}
			        send({'id': request_id, 'result': result})
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

		let activeThreads = try await server.threads(for: directory)
		#expect(activeThreads.map(\.id) == ["active-first", "active-second"])
		let archivedThreads = try await server.threads(
			for: directory,
			archived: true
		)
		#expect(archivedThreads.map(\.id) == ["archived-first", "archived-second"])
		try await server.renameThread(
			id: "active-first",
			name: "Renamed title"
		)
		try await server.archiveThread(id: "active-first")
		try await server.unarchiveThread(id: "archived-first")
		try await server.deleteThread(id: "active-second")

		let data = try Data(contentsOf: requestLog)
		let requests = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
		let listRequests = requests.filter
		{
			$0["method"] as? String == "thread/list"
		}
		#expect(listRequests.count == 4)
		for archived in [false, true]
		{
			let pages = listRequests.filter
			{
				($0["params"] as? [String: Any])?["archived"] as? Bool == archived
			}
			#expect(pages.count == 2)
			let first = try #require(pages.first?["params"] as? [String: Any])
			let second = try #require(pages.last?["params"] as? [String: Any])
			#expect(first["cwd"] as? String == directory.standardizedFileURL.path)
			#expect(first["limit"] as? Int == 100)
			#expect(first["sourceKinds"] as? [String] == ["appServer", "cli", "vscode"])
			#expect(second["cursor"] as? String ==
				(archived ? "archived-page-two" : "active-page-two"))
		}
		let managementRequests = requests.filter
		{
			$0["method"] as? String != "thread/list"
		}
		#expect(
			managementRequests.map
			{
				$0["method"] as? String
			} == [
				"thread/name/set",
				"thread/archive",
				"thread/unarchive",
				"thread/delete",
			]
		)
		#expect(
			managementRequests[0]["params"] as? [String: String] == [
				"threadId": "active-first",
				"name": "Renamed title",
			]
		)
		#expect(
			managementRequests[1]["params"] as? [String: String] == [
				"threadId": "active-first"
			]
		)
		#expect(
			managementRequests[2]["params"] as? [String: String] == [
				"threadId": "archived-first"
			]
		)
		#expect(managementRequests[3]["params"] as? [String: String] ==
			["threadId": "active-second"])
	}

	@Test func backendFailureCapturesBoundedDetailsAndReconnectResetsThem() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let runMarker = directory.appendingPathComponent("first-run-complete")
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import os
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			first_run = not os.path.exists('\(runMarker.path)')
			if first_run:
			    open('\(runMarker.path)', 'w').close()
			for line in sys.stdin:
			    message = json.loads(line)
			    if message.get('method') == 'initialize':
			        print(json.dumps({'id': message['id'], 'result': {}}), flush=True)
			    elif message.get('method') == 'account/read':
			        if first_run:
			            sys.stderr.write('a' * 16384)
			            sys.stderr.write('\\nOPENAI_API_KEY=sk-testsecret123456\\nfinal error\\n')
			            sys.stderr.flush()
			            sys.exit(7)
			        sys.stderr.write('fresh process\\n')
			        sys.stderr.flush()
			        print(json.dumps({'id': message['id'], 'result': {
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
		var disconnectMessage: String?
		server.onDisconnect =
		{
			disconnectMessage = $0
		}
		try await server.connect()
		_ = try? await server.accountStatus()
		for _ in 0 ..< 150 where disconnectMessage == nil
		{
			try await Task.sleep(for: .milliseconds(20))
		}

		let failedDiagnostics = server.backendDiagnostics
		#expect(disconnectMessage?.contains("app-server") == true)
		#expect(disconnectMessage?.contains("sk-testsecret") == false)
		#expect(failedDiagnostics.cliVersion == "codex-cli 0.153.2")
		#expect(failedDiagnostics.exitCode == 7)
		#expect(failedDiagnostics.stderrTail.utf8.count <= BackendDiagnosticsBuffer
			.maximumStderrBytes)
		#expect(failedDiagnostics.stderrTail.contains("final error"))
		#expect(failedDiagnostics.stderrTail.contains("OPENAI_API_KEY=[REDACTED]"))
		#expect(!failedDiagnostics.stderrTail.contains("sk-testsecret123456"))

		try await server.connect()
		_ = try await server.accountStatus()
		for _ in 0 ..< 50 where server.backendDiagnostics.stderrTail.isEmpty
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		let currentDiagnostics = server.backendDiagnostics
		#expect(currentDiagnostics.exitCode == nil)
		#expect(currentDiagnostics.stderrTail == "fresh process\n")
	}

	@Test func inheritedStderrDoesNotBlockFailureAndReconnect() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let runCount = directory.appendingPathComponent("app-server-runs")
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import os
			import sys
			import time

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			try:
			    runs = int(open('\(runCount.path)').read())
			except FileNotFoundError:
			    runs = 0
			open('\(runCount.path)', 'w').write(str(runs + 1))
			first_run = runs == 0

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    request_id = message.get('id')
			    if method == 'initialize':
			        print(json.dumps({'id': request_id, 'result': {}}), flush=True)
			    elif method == 'account/read' and first_run:
			        child = os.fork()
			        if child == 0:
			            os.close(0)
			            os.close(1)
			            time.sleep(2)
			            os._exit(0)
			        sys.stderr.write('final failure detail from parent\\n')
			        sys.stderr.flush()
			        os._exit(7)
			    elif method == 'account/read':
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
		var disconnectMessage: String?
		server.onDisconnect =
		{
			disconnectMessage = $0
		}
		try await server.connect()

		let clock = ContinuousClock()
		let startedAt = clock.now
		_ = try? await server.accountStatus()
		let failureDuration = startedAt.duration(to: clock.now)
		#expect(failureDuration < .seconds(1))
		#expect(disconnectMessage?.contains("app-server") == true)
		#expect(server.backendDiagnostics.stderrTail.contains("final failure detail from parent"))

		try await server.connect()
		#expect(server.backendDiagnostics.stderrTail.isEmpty)
		_ = try await server.accountStatus()
	}

	@Test func failedVersionReconnectPreservesPreviousDiagnostics() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let versionCount = directory.appendingPathComponent("version-runs")
		let executable = try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			import os
			import sys

			if '--version' in sys.argv:
			    try:
			        count = int(open('\(versionCount.path)').read())
			    except FileNotFoundError:
			        count = 0
			    open('\(versionCount.path)', 'w').write(str(count + 1))
			    print('codex-cli 0.153.2' if count == 0 else 'codex-cli 0.1.0')
			    sys.exit(0)

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    if method == 'initialize':
			        print(json.dumps({'id': message['id'], 'result': {}}), flush=True)
			    elif method == 'initialized':
			        sys.stderr.write('useful failure detail\\n')
			        sys.stderr.flush()
			        os._exit(7)
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
		for _ in 0 ..< 100 where server.backendDiagnostics.exitCode == nil
		{
			try await Task.sleep(for: .milliseconds(20))
		}
		let previousDiagnostics = server.backendDiagnostics
		#expect(previousDiagnostics.exitCode == 7)
		#expect(previousDiagnostics.stderrTail.contains("useful failure detail"))

		var reconnectError: AppServerError?
		do
		{
			try await server.connect()
		}
		catch let error as AppServerError
		{
			reconnectError = error
		}
		if let reconnectError
		{
			if case .incompatibleVersion = reconnectError
			{
				#expect(server.backendDiagnostics == previousDiagnostics)
			}
			else
			{
				#expect(
					Bool(false),
					"Expected an incompatible-version error"
				)
			}
		}
		else
		{
			#expect(
				Bool(false),
				"Expected reconnect to reject the old CLI version"
			)
		}
	}

	@Test func steeringAndProgressUseOwningThreadAndActiveTurn() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let requestLog = directory.appendingPathComponent("steering-request.json")
		let executable = try mockExecutable(
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

	@Test func skillInvocationAndRateLimitsUseInstalledProtocolShapes() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let requestLog = directory.appendingPathComponent("skill-turn-request.json")
		let executable = try makeSkillCatalogExecutable(
			in: directory,
			requestLog: requestLog
		)

		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var skillsChanged = 0
		var rateLimitsUpdated = 0
		server.onEvent =
		{
			event in
			switch event
			{
			case .skillsChanged: skillsChanged += 1
			case .rateLimitsUpdated: rateLimitsUpdated += 1
			default: break
			}
		}
		try await server.connect()

		let catalog = try await server.skills(for: directory)
		#expect(catalog.skills.count == 1)
		#expect(catalog.skills.first?.name == "review")
		#expect(catalog.skills.first?.defaultPrompt == "Review this change")
		#expect(catalog.errors.first?.message == "Invalid metadata")
		for _ in 0 ..< 100 where skillsChanged == 0
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(skillsChanged == 1)

		let limits = try await server.rateLimits()
		#expect(limits.accountId == "account-1")
		#expect(limits.rateLimits.primary?.usedPercent == 12.5)
		#expect(limits.rateLimits.primary?.resetsAt?.timeIntervalSince1970 == 1_730_947_200)
		#expect(limits.rateLimitsByLimitId?["codex"]?.planType == "plus")
		#expect(limits.rateLimitResetCredits?.availableCount == 1)
		#expect(limits.rateLimitResetCredits?.credits == nil)
		for _ in 0 ..< 100 where rateLimitsUpdated == 0
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(rateLimitsUpdated == 1)

		let turn = try await server.startTurn(
			threadId: "thread-1",
			text: "Check the parser",
			model: "gpt-6-sol",
			effort: "high",
			skills: [SkillReference(
				name: "review",
				path: "/tmp/review/SKILL.md"
			)]
		)
		#expect(turn.id == "turn-1")
		let request = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: requestLog)) as? [String: Any]
		)
		#expect(request["method"] as? String == "turn/start")
		let parameters = try #require(request["params"] as? [String: Any])
		#expect(parameters["model"] as? String == "gpt-6-sol")
		#expect(parameters["effort"] as? String == "high")
		let input = try #require(parameters["input"] as? [[String: Any]])
		#expect(input.count == 2)
		#expect(input[0]["text"] as? String == "$review Check the parser")
		#expect(input[1]["type"] as? String == "skill")
		#expect(input[1]["name"] as? String == "review")
		#expect(input[1]["path"] as? String == "/tmp/review/SKILL.md")
	}

	private func makeInteractionFlowExecutable(
		in directory: URL,
		responseLog: URL
	) throws -> URL
	{
		return try mockExecutable(
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

	private func makeCheckoutValidationExecutable(
		in directory: URL,
		requestLog: URL,
		responseMode: URL
	) throws -> URL
	{
		return try mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json
			from pathlib import Path
			import sys

			if '--version' in sys.argv:
			    print('codex-cli 0.153.2')
			    sys.exit(0)

			threads = {}
			requests = []
			response_mode = Path('\(responseMode.path)')
			def send(message):
			    print(json.dumps(message), flush=True)

			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    params = message.get('params', {})
			    request_id = message.get('id')
			    mode = response_mode.read_text() if response_mode.exists() else ''
			    if method == 'initialize':
			        send({'id': request_id, 'result': {}})
			        continue
			    requests.append(message)
			    with open('\(requestLog.path)', 'w') as output:
			        json.dump(requests, output)
			    if method == 'thread/start':
			        thread_id = 'thread-' + str(len(threads) + 1)
			        threads[thread_id] = params['cwd']
			        result = {'thread': {'id': thread_id, 'cwd': params['cwd']},
			                  'cwd': params['cwd']}
			        if mode == 'start-summary':
			            result['thread']['cwd'] = '/wrong-checkout'
			        elif mode == 'start-result':
			            result['cwd'] = '/wrong-checkout'
			    elif method == 'thread/resume':
			        cwd = threads[params['threadId']]
			        result = {'thread': {'id': params['threadId'], 'cwd': cwd}, 'cwd': cwd}
			    elif method == 'thread/turns/list':
			        result = {'data': [], 'nextCursor': None}
			    elif method == 'thread/list':
			        result = {'data': [{'id': thread_id, 'cwd': cwd}
			                           for thread_id, cwd in threads.items()
			                           if cwd == params['cwd']], 'nextCursor': None}
			        if mode == 'list':
			            result['data'].append({'id': 'foreign-thread', 'cwd': '/wrong-checkout'})
			    elif method == 'turn/start':
			        result = {'turn': {'id': 'turn-1', 'status': 'inProgress', 'items': []}}
			    else:
			        continue
			    send({'id': request_id, 'result': result})
			"""
		)
	}

	private func makeSkillCatalogExecutable(
		in directory: URL,
		requestLog: URL
	) throws -> URL
	{
		return try mockExecutable(
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
			    request_id = message.get('id')
			    if method == 'initialize':
			        send({'id': request_id, 'result': {}})
			    elif method == 'skills/list':
			        cwd = message['params']['cwds'][0]
			        send({'id': request_id, 'result': {'data': [{
			            'cwd': cwd,
			            'skills': [{
			                'name': 'review', 'description': 'Review a change',
			                'path': '/tmp/review/SKILL.md', 'scope': 'repo', 'enabled': True,
			                'pluginId': None,
			                'interface': {
			                    'displayName': 'Review', 'shortDescription': 'Check code',
			                    'defaultPrompt': 'Review this change',
			                    'iconSmallUrl': None, 'iconLargeUrl': None
			                }
			            }],
			            'errors': [{'path': '/tmp/broken/SKILL.md', 'message': 'Invalid metadata'}]
			        }]}})
			        send({'method': 'skills/changed', 'params': {}})
			    elif method == 'account/rateLimits/read':
			        limits = {
			            'limitId': 'codex', 'limitName': None,
			            'primary': {'usedPercent': 12.5, 'windowDurationMins': 300,
			                        'resetsAt': 1730947200},
			            'secondary': None, 'credits': None, 'individualLimit': None,
			            'spendControlReached': None, 'planType': 'plus',
			            'rateLimitReachedType': None
			        }
			        send({'id': request_id, 'result': {
			            'rateLimits': limits, 'rateLimitsByLimitId': {'codex': limits},
			            'rateLimitResetCredits': {'availableCount': 1, 'credits': None},
			            'accountId': 'account-1',
			            'rateLimitUpsell': None
			        }})
			        send({'method': 'account/rateLimits/updated', 'params': {
			            'rateLimits': limits
			        }})
			    elif method == 'turn/start':
			        with open('\(requestLog.path)', 'w') as output:
			            json.dump(message, output)
			        send({'id': request_id, 'result': {'turn': {
			            'id': 'turn-1', 'status': 'inProgress', 'items': [], 'error': None
			        }}})
			"""
		)
	}

	@Test(arguments: ["generated", "manual", "invalid", "failed"])
	func automaticTitlesStayOutsideTheUserTurnAndRespectManualNames(_ mode: String) async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let log = directory.appendingPathComponent("titles.jsonl")
		let executable = try mockExecutable(
			in: directory,
			script: """
		#!/usr/bin/env python3
		import json
		import sys
		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)
		def send(value):
		    print(json.dumps(value), flush=True)
		def complete():
		    text = json.dumps({'title': 'Create placeholder'})
		    if '\(mode)' == 'invalid':
		        text = 'invalid'
		    turn = {'id': 'title-turn', 'status': 'completed', 'items': [
		        {'id': 'title-message', 'type': 'agentMessage', 'text': text}]}
		    send({'method': 'turn/completed',
		          'params': {'threadId': 'helper', 'turn': turn}})
		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    if 'id' not in message:
		        continue
		    params = message.get('params', {})
		    with open('\(log.path)', 'a') as output:
		        output.write(json.dumps(message) + '\\n')
		    if method == 'thread/start':
		        if params.get('ephemeral') and '\(mode)' == 'failed':
		            send({'id': message['id'], 'error': {'code': -32000, 'message': 'Unavailable'}})
		            continue
		        tid = 'helper' if params.get('ephemeral') else 'task'
		        send({'id': message['id'], 'result': {
		            'thread': {'id': tid, 'cwd': '\(directory.path)'}, 'cwd': '\(directory.path)'}})
		    elif method == 'turn/start':
		        send({'id': message['id'], 'result': {
		            'turn': {'id': 'user-turn', 'status': 'inProgress', 'items': []}}})
		        if params['threadId'] == 'helper' and '\(mode)' != 'manual':
		            complete()
		    elif method == 'thread/name/set':
		        send({'id': message['id'], 'result': {}})
		        if params['name'] == 'My chosen name':
		            complete()
		    else:
		        send({'id': message['id'], 'result': {}})
		"""
		)
		let server = AppServer(executableOverride: executable)
		defer
		{
			server.disconnect()
		}
		var observedNames: [String] = []
		var helperContentEscaped = false
		server.onEvent =
		{
			event in
			if case .threadNameUpdated(
				let id,
				let name
			) = event, id == "task", let name
			{
				observedNames.append(name)
			}
			if let identity = event.turnContentIdentity, identity.threadID == "helper"
			{
				helperContentEscaped = true
			}
		}
		try await server.connect()
		let thread = try await server.startThread(
			in: directory,
			model: "selected-model"
		)
		let turn = try await server.startTurn(
			threadId: thread.summary.id,
			text: "Create a placeholder",
			model: "selected-model",
			effort: nil
		)
		#expect(turn.id == "user-turn")
		if mode == "manual"
		{
			for _ in 0 ..< 100
			{
				if !server.automaticTitleSessions.isEmpty
				{
					break
				}
				try await Task.sleep(for: .milliseconds(10))
			}
			#expect(!server.automaticTitleSessions.isEmpty)
			try await server.renameThread(
				id: "task",
				name: "My chosen name"
			)
		}
		for _ in 0 ..< 100
		{
			if server.automaticTitleJobs.isEmpty
			{
				break
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(server.automaticTitleJobs.isEmpty)
		#expect(!helperContentEscaped)
		#expect(observedNames == (mode == "generated" ? ["Create placeholder"] : []))
		let requests = try String(
			contentsOf: log,
			encoding: .utf8
		).split(separator: "\n").map
		{
			try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
		}
		let names = requests.filter
		{
			$0["method"] as? String == "thread/name/set"
		}.compactMap
		{
			($0["params"] as? [String: Any])?["name"] as? String
		}
		#expect(names == (mode == "manual" ? ["My chosen name"] :
				(mode == "generated" ? ["Create placeholder"] : [])))
		let helper = try #require(requests.first
		{
			($0["params"] as? [String: Any])?["ephemeral"] as? Bool == true
		})
		let parameters = try #require(helper["params"] as? [String: Any])
		#expect(parameters["model"] as? String == "selected-model")
		#expect(parameters["sandbox"] as? String == "read-only")
	}

	private func temporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				"CodexGUIIntegrationTests-\(UUID().uuidString)",
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}

	private func mockExecutable(
		in directory: URL,
		script: String
	) throws -> URL
	{
		let executable = directory.appendingPathComponent("mock-codex")
		try script.write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return executable
	}
}
