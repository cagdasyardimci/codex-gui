import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerConfiguredDefaultsTests
{
	@Test func capturedDefaultsReachTransportWithoutPresetOrTierLoss() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: """
			#!/usr/bin/env python3
			import json, sys
			if '--version' in sys.argv:
			    print('codex-cli 0.163.0')
			    sys.exit(0)
			captured = []
			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    if 'id' not in message:
			        continue
			    if method == 'turn/start':
			        captured.append(message['params'])
			        result = {'turn': {'id': 'turn-' + str(len(captured)),
			                           'status': 'inProgress', 'items': []}}
			    elif method == 'test/captured':
			        result = {'requests': captured}
			    else:
			        result = {}
			    print(json.dumps({'id': message['id'], 'result': result}), flush=True)
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
		let workspace = RunPreferences(
			approvalMode: .askForApproval,
			fastMode: false,
			configurationDefaults: RunConfigurationDefaults(
				approvalPolicy: .never,
				sandboxMode: .workspaceWrite,
				networkAccess: true,
				serviceTier: "flex"
			)
		)
		_ = try await server.startTurn(
			threadId: "workspace",
			inputs: [.text("Configured turn")],
			model: nil,
			effort: nil,
			skills: [],
			cwd: nil,
			preferences: workspace,
			collaborationMode: nil,
			serviceTier: "default"
		)
		let readOnly = RunPreferences(
			approvalMode: .fullAccess,
			fastMode: false,
			configurationDefaults: RunConfigurationDefaults(
				approvalPolicy: .onRequest,
				sandboxMode: .readOnly
			)
		)
		_ = try await server.startTurn(
			threadId: "readonly",
			inputs: [.text("Read-only turn")],
			model: nil,
			effort: nil,
			skills: [],
			cwd: nil,
			preferences: readOnly,
			collaborationMode: nil
		)
		let response = try await server.settingsRequest(
			"test/captured",
			params: [:]
		)
		let requests = try #require(response["requests"] as? [[String: Any]])
		try #require(requests.count == 2)
		#expect(requests[0]["approvalPolicy"] as? String == "never")
		#expect(requests[0]["serviceTierForTurn"] as? String == "flex")
		let sandbox = try #require(requests[0]["sandboxPolicy"] as? [String: Any])
		#expect(sandbox["type"] as? String == "workspaceWrite")
		#expect(sandbox["networkAccess"] as? Bool == true)
		#expect(requests[1]["approvalPolicy"] as? String == "on-request")
		#expect((requests[1]["sandboxPolicy"] as? [String: Any])?["type"] as? String == "readOnly")
	}
}
