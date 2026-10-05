import Foundation
import Testing

@testable import CodexGUI

struct BackendTests
{
	@Test func userMessageDecodingPreservesRawTextAndSeparateReferences() throws
	{
		let item = try #require(
			CodexItem(json: [
				"id": "user",
				"type": "userMessage",
				"content": [
					["type": "text", "text": "Inspect this"],
					["type": "mention", "name": "Example.swift", "path": "/tmp/Example.swift"],
					["type": "localImage", "path": "/tmp/image.png"],
				],
			])
		)
		#expect(item.text == "Inspect this")
		#expect(item.references.map(\.kind) == [.fileReference, .image])
		#expect(item.references.map(\.path) == ["/tmp/Example.swift", "/tmp/image.png"])
		#expect(
			UserMessagePresenter.body(for: item)
				== "Inspect this\n[File reference: Example.swift]"
		)
	}

	@Test func jsonLineFramerPreservesFragmentedAndAdjacentMessages()
	{
		let framer = JSONLineFramer()

		#expect(framer.append(Data("{\"id\":1".utf8)) == [])
		#expect(
			framer.append(Data("}\n{\"id\":2}\n{\"id\":3".utf8))
				== [Data("{\"id\":1}".utf8), Data("{\"id\":2}".utf8)]
		)
		#expect(framer.append(Data("}\n".utf8)) == [Data("{\"id\":3}".utf8)])
	}

	@Test func turnFixtureRetainsMessagesCommandsAndReportedFileDiff() throws
	{
		let fixture: [String: Any] = [
			"id": "turn-1",
			"status": "completed",
			"error": NSNull(),
			"items": [
				[
					"id": "user-1",
					"type": "userMessage",
					"content": [["type": "text", "text": "Update README"]],
				],
				[
					"id": "cmd-1",
					"type": "commandExecution",
					"command": "git status --short",
					"cwd": "/tmp/example",
					"aggregatedOutput": " M README.md\n",
					"status": "completed",
					"exitCode": 0,
					"durationMs": 125.5,
				],
				[
					"id": "change-1",
					"type": "fileChange",
					"status": "completed",
					"changes": [
						[
							"path": "README.md",
							"kind": "update",
							"diff": "@@ -1 +1 @@\n-old\n+new\n",
						]
					],
				],
			],
		]

		let turn = try #require(CodexTurn(json: fixture))
		#expect(turn.id == "turn-1")
		#expect(turn.items[0].text == "Update README")
		#expect(turn.items[1].command == "git status --short")
		#expect(turn.items[1].output == " M README.md\n")
		#expect(turn.items[1].exitCode == 0)
		#expect(turn.items[1].durationMs == 125.5)
		#expect(turn.items[2].changes[0].path == "README.md")
		#expect(turn.items[2].changes[0].diff == "@@ -1 +1 @@\n-old\n+new\n")
	}

	@Test func movedFileKeepsBackendReportedMovePath() throws
	{
		let change = try #require(
			FileChange(json: [
				"path": "Original.swift",
				"kind": ["type": "update", "move_path": "Destination.swift"],
				"diff": "@@ -1 +1 @@\n-old\n+new\n",
			])
		)
		#expect(change.kind == "update")
		#expect(change.movePath == "Destination.swift")
		#expect(change.path == "Original.swift")
		#expect(FileChange(json: ["path": "Unknown.swift"])?.kind == "unknown")
	}

	@Test func rateLimitWindowPreservesReportedResetTimeAndUnavailableWindows() throws
	{
		let snapshot = try #require(
			AccountRateLimitsSnapshot(json: [
				"rateLimits": [
					"limitId": "codex",
					"limitName": NSNull(),
					"primary": [
						"usedPercent": 25.5,
						"windowDurationMins": 15,
						"resetsAt": 1_730_947_200,
					],
					"secondary": NSNull(),
					"credits": NSNull(),
					"planType": "plus",
				],
				"rateLimitsByLimitId": NSNull(),
				"accountId": NSNull(),
			])
		)
		#expect(snapshot.rateLimits.limitId == "codex")
		#expect(snapshot.rateLimits.primary?.usedPercent == 25.5)
		#expect(snapshot.rateLimits.primary?.windowDurationMins == 15)
		#expect(snapshot.rateLimits.primary?.resetsAt?.timeIntervalSince1970 == 1_730_947_200)
		#expect(snapshot.rateLimits.secondary == nil)
		#expect(snapshot.rateLimits.credits == nil)
		#expect(snapshot.rateLimitsByLimitId == nil)
	}

	@Test func resetCreditSummaryPreservesCountAndOptionalDetails() throws
	{
		let details = try #require(
			RateLimitResetCreditsSummary(json: [
				"availableCount": 2,
				"credits": [
					[
						"id": "credit-1",
						"resetType": "codexRateLimits",
						"status": "available",
						"grantedAt": 1_781_654_400,
						"expiresAt": NSNull(),
						"title": "Rate-limit reset",
						"description": NSNull(),
					]
				],
			])
		)
		#expect(details.availableCount == 2)
		#expect(details.credits?.count == 1)
		#expect(details.credits?.first?.expiresAt == nil)
		#expect(details.credits?.first?.grantedAt.timeIntervalSince1970 == 1_781_654_400)

		let countOnly = try #require(
			RateLimitResetCreditsSummary(json: ["availableCount": 2, "credits": NSNull()])
		)
		#expect(countOnly.credits == nil)
	}

	@Test func modelFixtureUsesBackendModelIdentifierAndEfforts() throws
	{
		let model = try #require(
			ModelOption(json: [
				"id": "catalog-row-id",
				"model": "gpt-6-sol",
				"displayName": "GPT-6 Sol",
				"supportedReasoningEfforts": [
					["reasoningEffort": "low", "description": "Faster"],
					["reasoningEffort": "high", "description": "Deeper"],
				],
				"defaultReasoningEffort": "high",
				"isDefault": true,
			])
		)

		#expect(model.id == "gpt-6-sol")
		#expect(model.supportedReasoningEfforts == ["low", "high"])
		#expect(model.defaultReasoningEffort == "high")
	}

	@Test func planUpdateKeepsBackendStepStatusAndTurnIdentity() throws
	{
		let update = try #require(
			TurnPlanUpdate(json: [
				"threadId": "thread-2",
				"turnId": "turn-7",
				"explanation": "Checking the tests",
				"plan": [
					["step": "Inspect failures", "status": "completed"],
					["step": "Fix parser", "status": "inProgress"],
					["step": "Run checks", "status": "pending"],
				],
			])
		)

		#expect(update.threadId == "thread-2")
		#expect(update.turnId == "turn-7")
		#expect(update.explanation == "Checking the tests")
		#expect(update.plan.map(\.status) == [.completed, .inProgress, .pending])
		#expect(update.plan.map(\.step) == ["Inspect failures", "Fix parser", "Run checks"])
		#expect(
			TurnPlanUpdate(json: [
				"threadId": "thread-2",
				"turnId": "turn-7",
				"plan": [["step": "Unknown", "status": "almostDone"]],
			]) == nil
		)
	}

	@Test @MainActor func timedOutRequestDoesNotPoisonLaterResponses() async throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(
				"CodexGUIBackendTests-\(UUID().uuidString)",
				isDirectory: true
			)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = directory.appendingPathComponent("mock-codex")
		let script = """
		#!/usr/bin/env python3
		import json
		import sys

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		first_account_request_id = None
		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    if method == 'initialize':
		        print(
		            json.dumps({'id': message['id'], 'result': {'userAgent': 'mock'}}),
		            flush=True
		        )
		    elif method == 'account/read':
		        if first_account_request_id is None:
		            first_account_request_id = message['id']
		        else:
		            # The second request cannot arrive until Swift observes the first timeout.
		            print(json.dumps({'id': first_account_request_id, 'result': {
		                'account': {'type': 'chatgpt', 'email': 'late@example.com'},
		                'requiresOpenaiAuth': False
		            }}), flush=True)
		            print(json.dumps({'id': message['id'], 'result': {
		                'account': None, 'requiresOpenaiAuth': True
		            }}), flush=True)
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

		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .milliseconds(100)
		)
		try await server.connect()
		defer
		{
			server.disconnect()
		}

		do
		{
			_ = try await server.accountStatus()
			Issue.record("The first account/read should have timed out")
		}
		catch AppServerError.requestTimedOut(let method)
		{
			#expect(method == "account/read")
		}

		let secondStatus = try await server.accountStatus()
		#expect(secondStatus.requiresOpenAIAuth)
		#expect(secondStatus.type == nil)
	}
}
