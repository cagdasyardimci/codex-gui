import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerSkillAndRateLimitTests
{
	@Test func skillInvocationAndRateLimitsUseInstalledProtocolShapes() async throws
	{
		let directory = try AppServerTestExecutable.temporaryDirectory()
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
	private func makeSkillCatalogExecutable(
		in directory: URL,
		requestLog: URL
	) throws -> URL
	{
		return try AppServerTestExecutable.mockExecutable(
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
}
