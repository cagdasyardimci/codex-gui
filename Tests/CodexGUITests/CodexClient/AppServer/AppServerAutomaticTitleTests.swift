import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerAutomaticTitleTests
{
	@Test(arguments: ["generated", "manual", "invalid", "failed"])
	func automaticTitlesStayOutsideTheUserTurnAndRespectManualNames(_ mode: String) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let log = directory.appendingPathComponent("titles.jsonl")
		let executable = try await AppServerTestExecutable.mockExecutable(
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
}
