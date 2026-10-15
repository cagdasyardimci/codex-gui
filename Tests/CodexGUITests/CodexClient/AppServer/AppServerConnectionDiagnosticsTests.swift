import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerConnectionDiagnosticsTests
{
	@Test func backendFailureCapturesBoundedDetailsAndReconnectResetsThem() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let runMarker = directory.appendingPathComponent("first-run-complete")
		let executable = try await AppServerTestExecutable.mockExecutable(
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
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let runCount = directory.appendingPathComponent("app-server-runs")
		let executable = try await AppServerTestExecutable.mockExecutable(
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
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let versionCount = directory.appendingPathComponent("version-runs")
		let executable = try await AppServerTestExecutable.mockExecutable(
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
}
