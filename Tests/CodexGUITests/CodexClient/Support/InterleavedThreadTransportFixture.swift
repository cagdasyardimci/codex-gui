import Foundation
import Testing

/// A synthetic server: exercises the real subprocess transport without model inference.
struct InterleavedThreadTransportFixture: Sendable
{
	let directory: URL
	let executable: URL
	let log: URL

	init() throws
	{
		directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("InterleavedThreads-\(UUID().uuidString)")
		executable = directory.appendingPathComponent("mock-codex")
		log = directory.appendingPathComponent("requests.jsonl")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		try Self.script.write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
	}

	func requests() throws -> [[String: Any]]
	{
		try String(
			contentsOf: log,
			encoding: .utf8
		).split(separator: "\n").map
		{
			line in
			try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
		}
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import json
	from pathlib import Path
	import sys

	if '--version' in sys.argv:
	    print('codex-cli 0.160.0')
	    sys.exit(0)

	def send(message):
	    print(json.dumps(message, ensure_ascii=False), flush=True)

	def notify(method, owner, **values):
	    send({'method': method, 'params': {'threadId': owner, **values}})

	def turn(owner, status='inProgress'):
	    return {'id': owner + '-turn', 'status': status, 'items': []}

	def delta(owner, text):
	    notify('item/agentMessage/delta', owner, turnId=owner + '-turn',
	           itemId='shared-item', delta=text)

	starts = []
	active = set()
	approval_owners = {701: 'alpha', 702: 'beta'}
	for line in sys.stdin:
	    message = json.loads(line)
	    with (Path(__file__).parent / 'requests.jsonl').open('a') as output:
	        output.write(json.dumps(message) + '\n')
	    method = message.get('method')
	    params = message.get('params', {})
	    rid = message.get('id')
	    if method == 'initialize':
	        send({'id': rid, 'result': {}})
	    elif method == 'thread/start':
	        owner = params['owner']
	        send({'id': rid, 'result': {'thread': {'id': owner, 'cwd': params['cwd']}}})
	    elif method == 'turn/start':
	        starts.append((rid, params['threadId']))
	        if len(starts) == 2:
	            active.update(owner for _, owner in starts)
	            for response_id, owner in reversed(starts):
	                send({'id': response_id, 'result': {'turn': turn(owner)}})
	                notify('turn/started', owner, turn=turn(owner))
	            delta('alpha', 'A1\u2028')
	            delta('beta', 'B1')
	            for approval_id, owner in approval_owners.items():
	                send({'id': approval_id,
	                      'method': 'item/commandExecution/requestApproval',
	                      'params': {'threadId': owner, 'turnId': owner + '-turn',
	                                 'itemId': 'shared-item', 'command': 'printf synthetic',
	                                 'cwd': str(Path(__file__).parent)}})
	            delta('beta', 'B2')
	            delta('alpha', 'A2')
	    elif method == 'turn/steer':
	        owner = params['threadId']
	        if owner not in active or params['expectedTurnId'] != owner + '-turn':
	            send({'id': rid, 'error': {'code': -32600, 'message': 'wrong active turn'}})
	        else:
	            delta(owner, 'steered')
	            send({'id': rid, 'result': {'turnId': owner + '-turn'}})
	    elif method == 'turn/interrupt':
	        owner = params['threadId']
	        assert params['turnId'] == owner + '-turn'
	        active.remove(owner)
	        notify('turn/completed', owner, turn=turn(owner, 'interrupted'))
	        delta('beta', 'after-alpha-stop')
	        send({'id': rid, 'result': {}})
	    elif method is None and rid in approval_owners:
	        owner = approval_owners[rid]
	        expected = 'accept' if owner == 'alpha' else 'decline'
	        assert message['result']['decision'] == expected
	        notify('serverRequest/resolved', owner, requestId=rid)
	        if owner == 'beta':
	            notify('error', owner, turnId=owner + '-turn', willRetry=False,
	                   error={'message': 'synthetic beta failure'})
	            active.remove(owner)
	            notify('turn/completed', owner, turn=turn(owner, 'failed'))
	"""#
}
