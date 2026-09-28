import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerWorkspaceIsolationTests
{
	@Test func independentClientsKeepApprovalsStopSteeringAndReconnectSeparate() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let alpha = try fixture(in: directory.appendingPathComponent("alpha"))
		let beta = try fixture(in: directory.appendingPathComponent("beta"))
		let first = AppServer(
			executableOverride: alpha.executable,
			requestTimeout: .seconds(3)
		)
		let second = AppServer(
			executableOverride: beta.executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			first.disconnect()
			second.disconnect()
		}
		var firstInteractions: [PendingInteraction] = []
		var secondInteractions: [PendingInteraction] = []
		var firstStatuses: [String] = []
		var secondStatuses: [String] = []
		var secondResolutions: [String] = []
		first.onEvent =
		{
			event in
			if case .interaction(let interaction) = event
			{
				firstInteractions.append(interaction)
			}
			if case .turnCompleted(
				_,
				let turn
			) = event
			{
				firstStatuses.append(turn.status)
			}
		}
		second.onEvent =
		{
			event in
			if case .interaction(let interaction) = event
			{
				secondInteractions.append(interaction)
			}
			if case .turnCompleted(
				_,
				let turn
			) = event
			{
				secondStatuses.append(turn.status)
			}
			if case .interactionResolved(
				let owner,
				_
			) = event
			{
				secondResolutions.append(owner)
			}
		}

		async let firstConnection: Void = first.connect()
		async let secondConnection: Void = second.connect()
		_ = try await (firstConnection, secondConnection)
		let firstThread = try await first.startThread(in: alpha.directory)
		let secondThread = try await second.startThread(in: beta.directory)
		// Each server deliberately repeats thread, turn, item, and callback IDs.
		#expect(firstThread.summary.id == secondThread.summary.id)
		let inputs: [TurnInput] = [
			.text("Inspect the checkout"),
			.mention(
				name: "File.swift",
				path: beta.directory.appendingPathComponent("File.swift").path
			),
			.localImage(path: beta.directory.appendingPathComponent("screenshot.png").path),
		]
		async let firstStart = first.startTurn(
			threadId: firstThread.summary.id,
			inputs: [.text("First task")],
			model: nil,
			effort: nil,
			skills: [],
			cwd: alpha.directory
		)
		async let secondStart = second.startTurn(
			threadId: secondThread.summary.id,
			inputs: inputs,
			model: "gpt-6.1-sol",
			effort: "high",
			skills: [SkillReference(
				name: "review",
				path: "/tmp/review/SKILL.md"
			)],
			cwd: beta.directory
		)
		let (firstTurn, secondTurn) = try await (firstStart, secondStart)
		try await waitUntil
		{
			firstInteractions.count == 1 && secondInteractions.count == 1
		}
		let firstApproval = try #require(firstInteractions.first)
		let secondApproval = try #require(secondInteractions.first)
		#expect(firstApproval.id == secondApproval.id)
		#expect(firstApproval.cwd == alpha.directory.path)
		#expect(secondApproval.cwd == beta.directory.path)

		_ = try await second.steerTurn(
			threadId: secondThread.summary.id,
			expectedTurnId: secondTurn.id,
			inputs: inputs
		)
		try await first.interrupt(
			threadId: firstThread.summary.id,
			turnId: firstTurn.id
		)
		try await waitUntil
		{
			firstStatuses == ["interrupted"]
		}
		#expect(secondStatuses.isEmpty)
		first.disconnect()
		do
		{
			try first.respond(
				to: firstApproval.id,
				with: .approval(.accept)
			)
			Issue.record("Disconnected client's approval remained actionable")
		}
		catch let error as AppServerError
		{
			guard case .invalidInteraction = error
			else
			{
				throw error
			}
		}
		try await first.connect()
		#expect(
			try await first.resumeThread(
				id: firstThread.summary.id,
				expectedDirectory: alpha.directory
			).summary.cwd
				== alpha.directory.path
		)
		try second.respond(
			to: secondApproval.id,
			with: .approval(.decline)
		)
		try await waitUntil
		{
			secondStatuses == ["completed"] && secondResolutions.count == 1
		}
		#expect(secondResolutions == [secondThread.summary.id])

		let firstRequests = try requests(from: alpha.log)
		let secondRequests = try requests(from: beta.log)
		#expect(firstRequests.contains
		{
			$0["method"] as? String == "turn/interrupt"
		})
		#expect(!secondRequests.contains
		{
			$0["method"] as? String == "turn/interrupt"
		})
		#expect(!firstRequests.contains
		{
			$0["method"] as? String == "turn/steer"
		})
		let turnRequest = try #require(secondRequests
			.first
			{
				$0["method"] as? String == "turn/start"
			})
		let parameters = try #require(turnRequest["params"] as? [String: Any])
		#expect(parameters["cwd"] as? String == beta.directory.path)
		#expect(parameters["model"] as? String == "gpt-6.1-sol")
		#expect(parameters["effort"] as? String == "high")
		let encoded = try #require(parameters["input"] as? [[String: Any]])
		#expect(encoded.map
		{
			$0["type"] as? String
		} == ["text", "mention", "localImage", "skill"])
		#expect(encoded.first?["text"] as? String == "$review Inspect the checkout")
		#expect(
			encoded[1]["path"] as? String == beta.directory.appendingPathComponent("File.swift")
				.path
		)
		#expect(
			encoded[2]["path"] as? String == beta.directory.appendingPathComponent("screenshot.png")
				.path
		)
	}

	@Test func mismatchedResolutionCannotResolveAnsweredApprovalOrReplaceItsOwner() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let backend = try fixture(
			in: directory,
			injectMismatchedResolution: true
		)
		let server = AppServer(
			executableOverride: backend.executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var approvals: [PendingInteraction] = []
		var resolutions: [String] = []
		server.onEvent =
		{
			event in
			if case .interaction(let interaction) = event
			{
				approvals.append(interaction)
			}
			if case .interactionResolved(
				let owner,
				_
			) = event
			{
				resolutions.append(owner)
			}
		}
		try await server.connect()
		let thread = try await server.startThread(in: backend.directory)
		_ = try await server.startTurn(
			threadId: thread.summary.id,
			text: "Synthetic task"
		)
		try await waitUntil
		{
			approvals.count == 1
		}
		let approval = try #require(approvals.first)
		try server.respond(
			to: approval.id,
			with: .approval(.decline)
		)
		try await waitUntil
		{
			!resolutions.isEmpty
		}
		#expect(resolutions == [thread.summary.id])
		#expect(approvals.count == 1)
		do
		{
			try server.respond(
				to: approval.id,
				with: .approval(.accept)
			)
			Issue.record("A duplicate callback replaced the answered approval")
		}
		catch let error as AppServerError
		{
			guard case .invalidInteraction = error
			else
			{
				throw error
			}
		}
	}

	@Test func malformedResponseIDCannotCompleteAClientRequest() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let backend = try fixture(
			in: directory,
			injectMalformedResponseID: true
		)
		let server = AppServer(
			executableOverride: backend.executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let thread = try await server.startThread(in: backend.directory)
		#expect(thread.summary.cwd == backend.directory.path)
	}

	@Test func mismatchedThreadReadFailsBeforeLoadingItsHistory() async throws
	{
		let directory = try temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let backend = try fixture(in: directory)
		let server = AppServer(
			executableOverride: backend.executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		_ = try await server.startThread(in: backend.directory)
		do
		{
			_ = try await server.readThread(id: "another-thread")
			Issue.record("Read accepted a conversation belonging to another thread")
		}
		catch let error as AppServerError
		{
			guard case .protocolError = error
			else
			{
				throw error
			}
		}
		let recordedRequests = try requests(from: backend.log)
		#expect(!recordedRequests.contains
		{
			$0["method"] as? String == "thread/turns/list"
		})
	}

	private func waitUntil(_ predicate: () -> Bool) async throws
	{
		for _ in 0 ..< 100
		{
			if predicate()
			{
				return
			}
			try await Task.sleep(for: .milliseconds(20))
		}
		#expect(predicate())
	}

	private func requests(from log: URL) throws -> [[String: Any]]
	{
		let logContents = try String(
			contentsOf: log,
			encoding: .utf8
		)
		let lines = logContents.split(separator: "\n")
		return try lines.map
		{
			line in
			try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
		}
	}

	private func temporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				"CodexGUIWorkspaceWire-\(UUID().uuidString)",
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}

	private func fixture(
		in directory: URL,
		injectMismatchedResolution: Bool = false,
		injectMalformedResponseID: Bool = false
	) throws -> (executable: URL, directory: URL, log: URL)
	{
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let executable = directory.appendingPathComponent("mock-codex")
		let log = directory.appendingPathComponent("requests.jsonl")
		let cwdFile = directory.appendingPathComponent("cwd.json")
		let script = """
		#!/usr/bin/env python3
		import json
		from pathlib import Path
		import sys

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		def send(message):
		    print(json.dumps(message), flush=True)

		cwd_file = Path('\(cwdFile.path)')
		cwd = json.loads(cwd_file.read_text()) if cwd_file.exists() else ''
		for line in sys.stdin:
		    message = json.loads(line)
		    with open('\(log.path)', 'a') as output:
		        output.write(json.dumps(message) + '\\n')
		    method = message.get('method')
		    params = message.get('params', {})
		    request_id = message.get('id')
		    if method == 'initialize':
		        result = {}
		    elif method == 'thread/start':
		        cwd = params['cwd']
		        cwd_file.write_text(json.dumps(cwd))
		        result = {'thread': {'id': 'shared-thread', 'cwd': cwd}, 'cwd': cwd}
		        if \(injectMalformedResponseID ? "True" : "False"):
		            send({
		                'id': str(request_id),
		                'result': {'thread': {'id': 'string-response', 'cwd': '/wrong'}}
		            })
		            send({
		                'id': float(request_id),
		                'result': {'thread': {'id': 'float-response', 'cwd': '/wrong'}}
		            })
		    elif method in ('thread/read', 'thread/resume'):
		        result = {'thread': {'id': 'shared-thread', 'cwd': cwd}, 'cwd': cwd}
		    elif method == 'thread/turns/list':
		        result = {'data': [], 'nextCursor': None}
		    elif method == 'turn/start':
		        send({'id': request_id, 'result': {'turn': {
		            'id': 'shared-turn', 'status': 'inProgress', 'items': []}}})
		        send({'id': 13, 'method': 'item/commandExecution/requestApproval', 'params': {
		            'threadId': 'shared-thread', 'turnId': 'shared-turn', 'itemId': 'shared-item',
		            'cwd': cwd, 'command': 'printf synthetic', 'approvalId': 'shared-callback'}})
		        continue
		    elif method == 'turn/steer':
		        result = {'turnId': params['expectedTurnId']}
		    elif method == 'turn/interrupt':
		        send({'method': 'turn/completed', 'params': {'threadId': params['threadId'],
		              'turn': {'id': params['turnId'], 'status': 'interrupted', 'items': []}}})
		        result = {}
		    elif method is None and request_id == 13:
		        if \(injectMismatchedResolution ? "True" : "False"):
		            send({'method': 'serverRequest/resolved', 'params': {
		                'threadId': 'wrong-owner', 'requestId': request_id}})
		            send({'id': 13, 'method': 'item/commandExecution/requestApproval', 'params': {
		                'threadId': 'wrong-owner', 'turnId': 'wrong-turn', 'itemId': 'wrong-item'}})
		        send({'method': 'serverRequest/resolved', 'params': {
		            'threadId': 'shared-thread', 'requestId': request_id}})
		        send({'method': 'turn/completed', 'params': {'threadId': 'shared-thread',
		              'turn': {'id': 'shared-turn', 'status': 'completed', 'items': []}}})
		        continue
		    else:
		        continue
		    send({'id': request_id, 'result': result})
		"""
		try script.write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return (executable, directory.standardizedFileURL, log)
	}
}
