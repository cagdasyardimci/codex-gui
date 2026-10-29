import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerQueueTests
{
	@Test func queueRPCsUseCamelCaseIdentityAndConsumeEveryPageInOrder() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: Self.script
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		var invalidations: [String] = []
		server
			.onEvent =
			{
				if case .threadQueueChanged(let threadID) = $0
				{
					invalidations.append(threadID)
				}
			}
		try await server.connect()
		let input: [[String: Any]] = [
			["type": "text",
				"text": "Keep spans",
				"opaque": ["future": [1, 2]],
				"text_elements": [["byteRange": [
				"start": 0,
				"end": 4
				]]]],
			["type": "localImage", "path": "/tmp/image.png"]
		]
		let json = try JSONSerialization.data(
			withJSONObject: input,
			options: [.sortedKeys]
		)
		let added = try await server.addThreadQueue(
			threadID: "thread",
			inputJSON: json,
			clientUserMessageID: "stable-client"
		)
		#expect(added.clientUserMessageID == "stable-client")
		#expect(added.inputJSON == json)
		let updated = try await server.updateThreadQueue(
			threadID: "thread",
			queuedSubmissionID: added.id,
			inputJSON: json
		)
		#expect(updated.inputJSON == json)
		#expect(updated.id == added.id)
		#expect(updated.clientUserMessageID == added.clientUserMessageID)
		let all = try await server.allThreadQueue(threadID: "thread")
		#expect(all.map(\.id) == ["earlier", "queued"])
		try await server.reorderThreadQueue(
			threadID: "thread",
			queuedSubmissionIDs: ["queued", "earlier"]
		)
		let first = try await server.startThreadQueue(
			threadID: "thread",
			queuedSubmissionID: nil
		)
		#expect(first.id == "started")
		_ = try await server.startThreadQueue(
			threadID: "thread",
			queuedSubmissionID: "queued"
		)
		let deleted = try await server.deleteThreadQueue(
			threadID: "thread",
			queuedSubmissionID: "queued"
		)
		#expect(deleted)
		let steered = try await server.steerQueuedInput(
			threadID: "thread",
			expectedTurnID: "active",
			inputJSON: json
		)
		#expect(steered == "active")
		#expect(invalidations == ["thread"])
		let messages = try String(
			contentsOf: directory.appendingPathComponent("queue-rpcs.jsonl"),
			encoding: .utf8
		).split(separator: "\n")
			.map
			{
				try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
			}
		let initialized = try #require(messages
			.first
			{
				$0["method"] as? String == "initialize"
			}?["params"] as? [String: Any])
		#expect((initialized["capabilities"] as? [String: Any])?["experimentalApi"] as? Bool ==
			true)
		let lists = messages.filter
		{
			$0["method"] as? String == "thread/queue/list"
		}
		#expect(lists.count == 2)
		#expect((lists.last?["params"] as? [String: Any])?["cursor"] as? String == "next")
		let starts = messages.filter
		{
			$0["method"] as? String == "thread/queue/start"
		}
		.compactMap
		{
			$0["params"] as? [String: Any]
		}
		#expect(starts.first?["queuedSubmissionId"] == nil)
		#expect(starts.last?["queuedSubmissionId"] as? String == "queued")
		let add = try #require(messages
			.first
			{
				$0["method"] as? String == "thread/queue/add"
			}?["params"] as? [String: Any])
		#expect(add["clientUserMessageId"] as? String == "stable-client")
		#expect(add["threadId"] as? String == "thread")
		let inputs = try messages.filter
		{
			["thread/queue/add", "thread/queue/update", "turn/steer"]
				.contains($0["method"] as? String ?? "")
		}.map
		{
			let parameters = try #require($0["params"] as? [String: Any])
			return try JSONSerialization.data(
				withJSONObject: try #require(parameters["input"]),
				options: [.sortedKeys]
			)
		}
		#expect(inputs == [json, json, json])
	}

	@Test func queueFailuresRejectPaginationLoopsUnsupportedMethodsAndForeignIdentities(
	) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let server = AppServer(
			executableOverride: try await AppServerTestExecutable.mockExecutable(
				in: directory,
				script: Self.script
			),
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		do
		{
			_ = try await server.allThreadQueue(threadID: "cycle"); Issue
				.record("Repeated queue cursor was accepted")
		}
		catch AppServerError.protocolError
		{
		}
		do
		{
			_ = try await server.allThreadQueue(threadID: "unsupported"); Issue
				.record("Unsupported queue API appeared empty")
		}
		catch is ThreadQueueUnsupported
		{
		}
		let input = Data(#"[{"type":"text","text":"Preserve owner"}]"#.utf8)
		for operation in ["add", "update", "steer"]
		{
			do
			{
				switch operation
				{
				case "add":
					_ = try await server.addThreadQueue(
						threadID: "foreign-response",
						inputJSON: input,
						clientUserMessageID: "expected-client"
					)
				case "update":
					_ = try await server.updateThreadQueue(
						threadID: "foreign-response",
						queuedSubmissionID: "expected-submission",
						inputJSON: input
					)
				default:
					_ = try await server.steerQueuedInput(
						threadID: "foreign-response",
						expectedTurnID: "expected-turn",
						inputJSON: input
					)
				}
				Issue.record("Foreign response identity was accepted for \(operation)")
			}
			catch AppServerError.protocolError
			{
			}
		}
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import json, pathlib, sys
	if '--version' in sys.argv:
	    print('codex-cli 0.164.0')
	    sys.exit(0)
	root=pathlib.Path(__file__).parent
	queued={'id':'queued','clientUserMessageId':'stable-client',
	        'input':[{'type':'text','text':'New','text_elements':[]}]}
	def send(value): print(json.dumps(value), flush=True)
	for line in sys.stdin:
	    request=json.loads(line)
	    with (root/'queue-rpcs.jsonl').open('a') as log: log.write(json.dumps(request)+'\n')
	    if 'id' not in request: continue
	    method=request['method']; p=request.get('params',{}); result={}
	    if p.get('threadId')=='foreign-response':
	        if method=='turn/steer': result={'turnId':'foreign-turn'}
	        else:
	            result={'queuedSubmission':{'id':'foreign-submission',
	                    'clientUserMessageId':'foreign-client','input':p['input']}}
	        send({'id':request['id'],'result':result})
	        continue
	    if method=='initialize':
	        assert p['capabilities']['experimentalApi'] is True
	    elif method=='thread/queue/add':
	        assert p['threadId']=='thread'
	        queued={'id':'queued','clientUserMessageId':p['clientUserMessageId'],
	                'input':p['input']}
	        result={'queuedSubmission':queued}
	        send({'method':'thread/queue/changed','params':{'threadId':p['threadId']}})
	    elif method=='thread/queue/update':
	        assert p['queuedSubmissionId']==queued['id']
	        queued['input']=p['input']; result={'queuedSubmission':queued}
	    elif method=='thread/queue/list':
	        if p['threadId']=='unsupported':
	            send({'id':request['id'],
	                  'error':{'code':-32601,'message':'Method not found'}})
	            continue
	        cycle=p['threadId']=='cycle'
	        if p.get('cursor'):
	            value=dict(queued); value['id']='cycle-tail' if cycle else 'queued'
	            result={'data':[value], 'nextCursor':'next' if cycle else None}
	        else:
	            earlier={'id':'earlier','clientUserMessageId':'earlier-client',
	                     'input':[{'type':'text','text':'Earlier','text_elements':[]}]}
	            result={'data':[earlier], 'nextCursor':'next'}
	    elif method=='thread/queue/reorder':
	        assert p['queuedSubmissionIds']==['queued','earlier']
	    elif method=='thread/queue/delete':
	        assert p['queuedSubmissionId']=='queued'; result={'deleted':True}
	    elif method=='turn/steer':
	        assert p['threadId']=='thread' and p['expectedTurnId']=='active'
	        assert p['input']==queued['input']
	        result={'turnId':'active'}
	    elif method=='thread/queue/start':
	        assert 'queuedSubmissionId' not in p or p['queuedSubmissionId']=='queued'
	        result={'turn':{'id':'started','status':'inProgress','items':[]}}
	    send({'id':request['id'],'result':result})
	"""#
}
