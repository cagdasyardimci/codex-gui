import Foundation

@testable import CodexGUI

@MainActor
struct AppServerListHistoryFixture
{
	let server: AppServer
	let directory: URL

	static func make() throws -> Self
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("AppServerTransportWriterTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let executable = directory.appendingPathComponent("mock-codex")
		try """
		#!/usr/bin/env python3
		import json
		import pathlib
		import sys

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		directory = pathlib.Path(__file__).parent
		list_counts = {}
		def send(value):
		    print(json.dumps(value, ensure_ascii=False), flush=True)

		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    with open(directory / 'messages.jsonl', 'a') as log:
		        log.write(json.dumps(message) + '\\n')
		    if method == 'initialize':
		        send({'id': message['id'], 'result': {}})
		    elif method in ('model/list', 'thread/list'):
		        list_counts[method] = list_counts.get(method, 0) + 1
		        if method == 'model/list':
		            rows = [{'model': 'fixture-model', 'displayName': 'Fixture model'}]
		        else:
		            rows = [{'id': 'listed-thread', 'cwd': message['params']['cwd']}]
		        # Terminate even without cycle rejection so a regression cannot hang the test.
		        cursor = 'repeated-list-cursor' if list_counts[method] < 3 else None
		        send({'id': message['id'], 'result': {'data': rows, 'nextCursor': cursor}})
		    elif method == 'thread/turns/list':
		        text = chr(0xE9) + ' e' + chr(0x301) + '🧪' + chr(0x2028) + '終'
		        send({'id': message['id'], 'result': {'nextCursor': 'next-cursor', 'data': [
		            {'id': 'latest', 'status': 'completed', 'items': [
		                {'id': 'user', 'type': 'userMessage', 'content': [
		                    {'type': 'text', 'text': text}, {'type': 'text', 'text': 'second'}
		                ]}, {'type': 'agentMessage', 'text': 'missing ID'}
		            ]}, {'id': 'earlier', 'items': []}
		        ]}})
		    elif method == 'thread/items/list':
		        params = message['params']
		        turn_id = 'other-turn' if params.get('turnId') == 'foreign' else params['turnId']
		        if params.get('sortDirection') == 'desc':
		            item = {'id': 'reply', 'type': 'agentMessage', 'text': 'Selected reply'}
		            cursor = 'previous-items'
		        elif params.get('cursor') == 'next-items':
		            item = {'id': 'reply', 'type': 'agentMessage', 'text': 'Selected reply'}
		            cursor = None
		        else:
		            content = [{'type': 'text', 'text': 'Selected request'}]
		            item = {'id': 'request', 'type': 'userMessage', 'content': content}
		            cursor = 'next-items'
		        result = {'data': [{'turnId': turn_id, 'item': item}], 'nextCursor': cursor}
		        send({'id': message['id'], 'result': result})
		""".write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return Self(
			server: AppServer(
				executableOverride: executable,
				requestTimeout: .seconds(3)
			),
			directory: directory
		)
	}

	func messages() -> [[String: Any]]
	{
		guard let data = try? Data(contentsOf: directory.appendingPathComponent("messages.jsonl"))
		else
		{
			return []
		}
		return data.split(separator: 0x0A).compactMap
		{
			(try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
		}
	}

	func methods() -> [String]
	{
		messages().compactMap
		{
			$0["method"] as? String
		}
	}

	func close()
	{
		server.disconnect()
		try? FileManager.default.removeItem(at: directory)
	}
}
