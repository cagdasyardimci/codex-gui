import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerResponseDeliveryTests
{
	@Test func largeNestedResponsePreservesValuesAndEveryAdjacentNotification() async throws
	{
		let (server, directory) = try fixture()
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		var deltas: [String] = []
		server.onEvent =
		{
			if case .agentMessageDelta(
				_,
				_,
				_,
				let text
			) = $0
			{
				deltas.append(text)
			}
		}
		try await server.connect()
		let response = try await server.request(
			"response/large",
			params: [:]
		)
		let expectedText = String(
			repeating: "x",
			count: 512 * 1024
		) + "\u{00E9}e\u{0301}\u{2028}終"
		let text = try #require(response["text"] as? String)
		#expect(text.utf8.elementsEqual(expectedText.utf8))
		#expect(response["null"] is NSNull)
		let nested = try #require(response["nested"] as? [String: Any])
		let values = try #require(nested["values"] as? [Any])
		#expect(values.count == 7)
		#expect(values[0] as? Bool == false)
		#expect(JSONRPCRequestID(json: values[0]) == nil)
		#expect(values[1] as? Bool == true)
		#expect(JSONRPCRequestID(json: values[1]) == nil)
		#expect(JSONRPCRequestID(json: values[2]) == .integer(0))
		#expect(JSONRPCRequestID(json: values[3]) == .integer(9_007_199_254_740_993))
		#expect((values[4] as? NSNumber)?.doubleValue == 4.25)
		#expect(values[5] is NSNull)
		#expect((values[6] as? NSNumber)?.doubleValue == 1.25e40)
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(3))
		while deltas.count < 256, clock.now < deadline
		{
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(deltas == (0 ..< 256).map(String.init))
	}

	@Test func invalidResponseShapesAndServerErrorsKeepTheirExistingFailureBehavior() async throws
	{
		let (server, directory) = try fixture()
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		try await server.connect()
		for shape in ["null", "array", "scalar", "missing", "invalid-error"]
		{
			do
			{
				_ = try await server.request(
					"response/invalid",
					params: ["shape": shape]
				)
				Issue.record("Accepted invalid response shape: \(shape)")
			}
			catch AppServerError.protocolError(let message)
			{
				#expect(message == "Invalid response from app-server")
			}
		}
		do
		{
			_ = try await server.request(
				"response/rejected",
				params: [:]
			)
			Issue.record("Expected server rejection")
		}
		catch AppServerError.requestRejected(let message)
		{
			#expect(message == "fixture rejection")
		}
		let recovered = try await server.request(
			"response/identity",
			params: [:]
		)
		#expect(recovered["owner"] as? String == "integer request")
	}

	@Test func resultDomainDecodingMatchesTheLegacyJSONRoundTrip() async throws
	{
		let (server, directory) = try fixture()
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		try await server.connect()
		let response = try await server.request(
			"response/domain",
			params: [:]
		)
		let legacy = try #require(JSONSerialization.jsonObject(
			with: JSONSerialization.data(withJSONObject: response)
		) as? [String: Any])
		let turn = try #require((response["turn"] as? [String: Any]).flatMap(CodexTurn.init(json:)))
		let legacyTurn = try #require((legacy["turn"] as? [String: Any])
			.flatMap(CodexTurn.init(json:)))
		#expect(turn.id == legacyTurn.id)
		#expect(turn.status == legacyTurn.status)
		#expect(turn.startedAt == legacyTurn.startedAt)
		#expect(turn.completedAt == legacyTurn.completedAt)
		#expect(turn.durationMs == legacyTurn.durationMs)
		let command = try #require(turn.items.first)
		let legacyCommand = try #require(legacyTurn.items.first)
		#expect(command.command == legacyCommand.command)
		#expect(command.exitCode == legacyCommand.exitCode)
		#expect(command.durationMs == legacyCommand.durationMs)
		#expect(command.output?.utf8.elementsEqual(try #require(legacyCommand.output).utf8) == true)
		#expect(command.changes == legacyCommand.changes)
		#expect(AccountRateLimitsSnapshot(json: response) ==
			AccountRateLimitsSnapshot(json: legacy))
	}

	@Test func responsesArrivingInReverseOrderResumeTheirMatchingRequests() async throws
	{
		let (server, directory) = try fixture()
		defer
		{
			server.disconnect()
			try? FileManager.default.removeItem(at: directory)
		}
		try await server.connect()
		let first = Task
		{
			let response = try await server.request(
				"response/reverse",
				params: ["name": "first"]
			)
			return response["name"] as? String
		}
		let second = Task
		{
			let response = try await server.request(
				"response/reverse",
				params: ["name": "second"]
			)
			return response["name"] as? String
		}
		#expect(try await first.value == "first")
		#expect(try await second.value == "second")
	}

	private func fixture() throws -> (AppServer, URL)
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("AppServerResponseDeliveryTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let executable = directory.appendingPathComponent("mock-codex")
		try """
		#!/usr/bin/env python3
		import json
		import sys

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		def send(message):
		    print(json.dumps(message, ensure_ascii=False), flush=True)

		def delta(index):
		    send({'method': 'item/agentMessage/delta', 'params': {
		        'threadId': 'thread', 'turnId': 'turn', 'itemId': 'agent', 'delta': str(index)
		    }})

		reversed_requests = []

		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    request_id = message.get('id')
		    if method == 'initialize':
		        send({'id': request_id, 'result': {}})
		    elif method == 'response/large':
		        for index in range(128):
		            delta(index)
		        send({'id': request_id, 'result': {
		            'text': 'x' * (512 * 1024) + chr(0xE9) + 'e' + chr(0x301) + chr(0x2028) + '終',
		            'null': None,
		            'nested': {'values': [False, True, 0, 9007199254740993, 4.25, None, 1.25e40]}
		        }})
		        for index in range(128, 256):
		            delta(index)
		    elif method == 'response/invalid':
		        shape = message['params']['shape']
		        response = {'id': request_id}
		        if shape in ('null', 'array', 'scalar'):
		            response['result'] = {'null': None, 'array': [], 'scalar': 'text'}[shape]
		        elif shape == 'invalid-error':
		            response['error'] = {'code': True, 'message': 'invalid boolean code'}
		        send(response)
		    elif method == 'response/rejected':
		        send({'id': request_id, 'error': {'code': -32600, 'message': 'fixture rejection'}})
		    elif method == 'response/identity':
		        for wrong_id in (str(request_id), float(request_id), True):
		            send({'id': wrong_id, 'result': {'owner': 'incorrect request'}})
		        send({'id': request_id, 'result': {'owner': 'integer request'}})
		        send({'id': request_id, 'error': {'code': -32600, 'message': 'late duplicate'}})
		    elif method == 'response/reverse':
		        reversed_requests.append((request_id, message['params']['name']))
		        if len(reversed_requests) == 2:
		            for response_id, name in reversed(reversed_requests):
		                send({'id': response_id, 'result': {'name': name}})
		            reversed_requests.clear()
		    elif method == 'response/domain':
		        send({'id': request_id, 'result': {
		            'turn': {
		                'id': 'turn', 'status': 'completed', 'startedAt': 100.0,
		                'completedAt': 101.25, 'durationMs': 1250.0,
		                'items': [{'id': 'command', 'type': 'commandExecution',
		                           'command': 'swift test', 'exitCode': 0.0, 'durationMs': 1250.0,
		                           'aggregatedOutput': chr(0xE9) + 'e' + chr(0x301), 'changes': []}]
		            },
		            'rateLimits': {'primary': {'usedPercent': 10.0, 'windowDurationMins': 300.0,
		                                       'resetsAt': 1730947200.0}},
		            'rateLimitResetCredits': {'availableCount': 1.0, 'credits': None}
		        }})
		""".write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return (AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		), directory)
	}
}
