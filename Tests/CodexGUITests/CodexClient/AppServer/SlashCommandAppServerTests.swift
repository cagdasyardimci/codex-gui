import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct SlashCommandAppServerTests
{
	@Test func capturedFastTierUsesAdvertisedIDAndMissingTierDoesNotSendRPC() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let server = AppServer(
			executableOverride: try makeExecutable(in: directory),
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let preferences = RunPreferences(
			approvalMode: .askForApproval,
			fastMode: true
		)
		_ = try await server.startTurn(
			threadId: "source",
			inputs: [.text("Inspect")],
			model: "model",
			effort: "high",
			skills: [],
			cwd: nil,
			preferences: preferences,
			collaborationMode: nil,
			serviceTier: "express"
		)
		do
		{
			_ = try await server.startTurn(
				threadId: "source",
				inputs: [.text("Inspect")],
				model: "model",
				effort: "high",
				skills: [],
				cwd: nil,
				preferences: preferences,
				collaborationMode: nil,
				serviceTier: nil
			)
			Issue.record("Expected missing captured tier to fail before sending")
		}
		catch AppServerError.requestRejected
		{
		}
		let requests = try readRequests(in: directory)
		let turn = try parameters(
			for: "turn/start",
			in: requests
		)
		#expect(turn["serviceTierForTurn"] as? String == "express")
		let turnRequests = requests.filter
		{
			$0["method"] as? String == "turn/start"
		}
		#expect(turnRequests.count == 1)
	}

	@Test func forkRequestKeepsHistoryAndInstalledWireShape() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try makeExecutable(in: directory)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let fork = try await server.forkThread(
			id: "source",
			expectedDirectory: directory
		)
		#expect(fork.summary.id == "forked")
		#expect(fork.settings?.model == "model")
		#expect(fork.turns.first?.id == "history")
		#expect(fork.nextTurnsCursor == "older")

		let requests = try readRequests(in: directory)
		let initialize = try parameters(
			for: "initialize",
			in: requests
		)
		let capabilities = initialize["capabilities"] as? [String: Any]
		#expect(capabilities?["experimentalApi"] as? Bool == true)
		let forkParameters = try parameters(
			for: "thread/fork",
			in: requests
		)
		#expect(forkParameters["threadId"] as? String == "source")
		#expect(forkParameters["excludeTurns"] as? Bool == true)
		#expect(forkParameters["deferGoalContinuation"] as? Bool == true)
		#expect(forkParameters["cwd"] == nil)
		#expect(try parameters(
			for: "thread/turns/list",
			in: requests
		)["threadId"] as? String ==
			"forked")
	}

	@Test func compactionAcknowledgementKeepsLifecycleOpen() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try makeExecutable(in: directory)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var lifecycle: [String] = []
		server.onEvent =
		{
			event in
			switch event
			{
			case .turnStarted(
				let threadID,
				let turn
			):
				lifecycle.append("start:\(threadID):\(turn.id)")
			case .itemStarted(
				let threadID,
				let turnID,
				let item
			):
				lifecycle.append("item:\(threadID):\(turnID):\(item.type)")
			case .turnCompleted: lifecycle.append("completed")
			default: break
			}
		}
		try await server.connect()
		try await server.compactThread(id: "source")
		#expect(lifecycle == [
			"start:source:compact-turn",
			"item:source:compact-turn:contextCompaction"
		])

		let requests = try readRequests(in: directory)
		#expect(try parameters(
			for: "thread/compact/start",
			in: requests
		)["threadId"] as? String ==
			"source")
	}

	@Test func reviewRequestsPreserveInlineAndDetachedDelivery() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try makeExecutable(in: directory)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let review = try await server.startReview(
			threadId: "source",
			target: .uncommittedChanges
		)
		#expect(review.reviewThreadId == "source")
		#expect(review.turn.id == "review-turn")
		#expect(review.turn.items.first?.text == "Current changes")
		let detached = try await server.startReview(
			threadId: "source",
			target: .baseBranch(branch: "main"),
			delivery: .detached
		)
		#expect(detached.reviewThreadId == "detached-review")

		let requests = try readRequests(in: directory)
		let inline = try parameters(
			for: "review/start",
			in: requests
		)
		#expect(inline["delivery"] as? String == "inline")
		#expect((inline["target"] as? [String: Any])?["type"] as? String == "uncommittedChanges")
	}

	@Test func collaborationSettingsAndTurnInputUseInstalledShapes() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try makeExecutable(in: directory)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let modes = try await server.collaborationModes()
		#expect(modes.map(\.mode) == [.plan, .default])
		#expect(modes.first?.model == nil)
		let mode = CollaborationMode(
			mode: .plan,
			model: "model",
			reasoningEffort: "high"
		)
		try await server.updateThreadSettings(
			id: "source",
			settings: ThreadSettingsUpdate(collaborationMode: mode)
		)
		let turn = try await server.startTurn(
			threadId: "source",
			inputs: [.text("Inspect parser")],
			model: "model",
			effort: "high",
			skills: [],
			cwd: directory,
			preferences: .standard,
			collaborationMode: mode
		)
		#expect(turn.id == "normal-turn")

		let requests = try readRequests(in: directory)
		let update = try parameters(
			for: "thread/settings/update",
			in: requests
		)
		let captured = try parameters(
			for: "turn/start",
			in: requests
		)
		for value in [update, captured]
		{
			let collaboration = try #require(value["collaborationMode"] as? [String: Any])
			#expect(collaboration["mode"] as? String == "plan")
			let settings = try #require(collaboration["settings"] as? [String: Any])
			#expect(settings["model"] as? String == "model")
			#expect(settings["reasoning_effort"] as? String == "high")
			#expect(settings["developer_instructions"] is NSNull)
		}
		#expect(update["input"] == nil)
		let turnRequests = requests.filter
		{
			$0["method"] as? String == "turn/start"
		}
		#expect(turnRequests.count == 1)
		let inputs = captured["input"] as? [[String: Any]]
		#expect(inputs?.first?["text"] as? String == "Inspect parser")
	}

	@Test func invalidForkAndInlineReviewAcksAreRejectedLocally() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let server = AppServer(
			executableOverride: try makeExecutable(in: directory),
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		do
		{
			_ = try await server.forkThread(
				id: "source",
				expectedDirectory: directory
					.appendingPathComponent("other")
			)
			Issue.record("Expected checkout mismatch")
		}
		catch
		{
			#expect(error.localizedDescription.contains("checkout"))
		}
		do
		{
			_ = try await server.startReview(
				threadId: "wrong-owner",
				target: .uncommittedChanges
			)
			Issue.record("Expected inline owner validation")
		}
		catch AppServerError.protocolError
		{
		}
		let requests = try readRequests(in: directory)
		#expect(!requests.contains
		{
			$0["method"] as? String == "thread/turns/list"
		})
	}

	@Test func definiteServerRejectionRemainsDistinctFromMalformedAcknowledgement() async throws
	{
		let directory = try makeDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let server = AppServer(
			executableOverride: try makeExecutable(in: directory),
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		do
		{
			try await server.compactThread(id: "unsupported")
			Issue.record("Expected server rejection")
		}
		catch AppServerError.requestRejected(let message)
		{
			#expect(message == "Unsupported compaction")
		}
		do
		{
			_ = try await server.request(
				"malformed",
				params: [:]
			)
			Issue.record("Expected malformed acknowledgement")
		}
		catch AppServerError.protocolError
		{
		}
	}

	private func makeDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("SlashCommandAppServerTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory.standardizedFileURL
	}

	private func parameters(
		for method: String,
		in requests: [[String: Any]]
	) throws -> [String: Any]
	{
		let request = try #require(requests.first
		{
			$0["method"] as? String == method
		})
		return try #require(request["params"] as? [String: Any])
	}

	private func readRequests(in directory: URL) throws -> [[String: Any]]
	{
		let log = try String(
			contentsOf: directory.appendingPathComponent("requests.jsonl"),
			encoding: .utf8
		)
		let lines = log.split(separator: "\n")
		return try lines.map
		{
			try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
		}
	}

	private func makeExecutable(in directory: URL) throws -> URL
	{
		let executable = directory.appendingPathComponent("mock-codex")
		let script = """
		#!/usr/bin/env python3
		import json
		import sys
		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)
		cwd = '\(directory.path)'
		def send(value):
		    print(json.dumps(value), flush=True)
		for line in sys.stdin:
		    message = json.loads(line)
		    with open(cwd + '/requests.jsonl', 'a') as log:
		        log.write(json.dumps(message) + '\\n')
		    if 'id' not in message:
		        continue
		    method = message['method']
		    params = message.get('params', {})
		    result = {}
		    if method == 'thread/fork':
		        result = {'thread': {'id': 'forked', 'cwd': cwd}, 'cwd': cwd,
		                  'model': 'model', 'modelProvider': 'openai',
		                  'approvalPolicy': 'on-request', 'approvalsReviewer': 'user',
		                  'sandbox': {'type': 'workspaceWrite'}}
		    elif method == 'thread/turns/list':
		        result = {'data': [{'id': 'history', 'status': 'completed', 'items': []}],
		                  'nextCursor': 'older'}
		    elif method == 'thread/compact/start':
		        if params['threadId'] == 'unsupported':
		            send({'id': message['id'], 'error': {
		                'code': -32601, 'message': 'Unsupported compaction'}})
		            continue
		        send({'method': 'turn/started', 'params': {'threadId': 'source',
		              'turn': {'id': 'compact-turn', 'status': 'inProgress', 'items': []}}})
		        send({'method': 'item/started', 'params': {'threadId': 'source',
		              'turnId': 'compact-turn', 'item': {'id': 'compact-item',
		              'type': 'contextCompaction'}}})
		    elif method == 'review/start':
		        owner = 'detached-review' if params['delivery'] == 'detached' else 'source'
		        result = {'reviewThreadId': owner, 'turn': {'id': 'review-turn',
		                  'status': 'inProgress', 'items': [{'id': 'review-item',
		                  'type': 'enteredReviewMode', 'review': 'Current changes'}]}}
		    elif method == 'collaborationMode/list':
		        result = {'data': [{'name': 'Plan', 'mode': 'plan', 'model': None},
		                          {'name': 'Default', 'mode': 'default', 'model': None}]}
		    elif method == 'turn/start':
		        result = {'turn': {'id': 'normal-turn', 'status': 'inProgress', 'items': []}}
		    elif method == 'malformed':
		        send({'id': message['id'], 'error': {'message': 'Missing integer code'}})
		        continue
		    send({'id': message['id'], 'result': result})
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
		return executable
	}
}
