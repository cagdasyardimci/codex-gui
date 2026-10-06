import Foundation
import Testing

@testable import CodexGUI

struct AppServerRequestTimeoutTests
{
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
