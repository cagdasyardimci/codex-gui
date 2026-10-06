import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerThreadManagementTests
{
	@Test func checkoutCwdIsCheckedOnStartResumeListAndTurnOverride() async throws
	{
		let directory = try AppServerTestExecutable.temporaryDirectory()
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
		let directory = try AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let requestLog = directory.appendingPathComponent("requests.json")
		let executable = try AppServerTestExecutable.mockExecutable(
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
	private func makeCheckoutValidationExecutable(
		in directory: URL,
		requestLog: URL,
		responseMode: URL
	) throws -> URL
	{
		return try AppServerTestExecutable.mockExecutable(
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
}
