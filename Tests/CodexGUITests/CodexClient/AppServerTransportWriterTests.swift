import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerTransportWriterTests
{
	@Test func requestDeadlineRunsWhileItsPhysicalWriteIsBlocked() async throws
	{
		let fixture = try fixture(timeout: .milliseconds(250))
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.isPaused
		}
		var disconnectMessage: String?
		fixture.server.onDisconnect =
		{
			disconnectMessage = $0
		}
		let clock = ContinuousClock()
		let started = clock.now
		let request = Task
		{
			_ = try await fixture.server.request(
				"fixture/largeMutation",
				params: ["text": String(
					repeating: "x",
					count: 1_048_576
				)]
			)
		}
		var mainActorAdvanced = false
		await Task
		{
			mainActorAdvanced = true
		}.value
		#expect(mainActorAdvanced)
		do
		{
			_ = try await request.value
			Issue.record("A request blocked in a full pipe unexpectedly completed.")
		}
		catch AppServerError.requestTimedOut(let method)
		{
			#expect(method == "fixture/largeMutation")
		}
		#expect(started.duration(to: clock.now) < .seconds(2))
		#expect(disconnectMessage?.contains("input failed") == true)
	}

	@Test func cancellingAQueuedRequestSendsNoBytesAndKeepsConnectionUsable() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.isPaused
		}
		let blocked = try fixture.server.send([
			"method": "fixture/blocker",
			"params": ["text": String(
				repeating: "x",
				count: 1_048_576
			)],
		])
		try await waitUntil
		{
			blocked.hasIncompleteFrame
		}
		var started = false
		let queued = Task
		{
			started = true
			_ = try await fixture.server.request(
				"fixture/mustNotSend",
				params: [:]
			)
		}
		try await waitUntil
		{
			started
		}
		queued.cancel()
		do
		{
			_ = try await queued.value
			Issue.record("The cancelled queued request unexpectedly completed.")
		}
		catch let failure as ProtocolWriteFailure
		{
			#expect(failure.cause is CancellationError)
			#expect(!failure.mayHaveBeenSent)
			#expect(!failure.requiresDisconnect)
		}
		#expect(blocked.hasIncompleteFrame)
		try fixture.release()
		try await blocked.wait()
		let result = try await fixture.server.request(
			"fixture/afterCancel",
			params: [:]
		)
		#expect(result["method"] as? String == "fixture/afterCancel")
		#expect(!fixture.methods().contains("fixture/mustNotSend"))
		#expect(fixture.methods().prefix(3) == ["initialize", "initialized", "fixture/blocker"])
	}

	@Test func synchronousApprovalKeepsMetadataUntilAcknowledgmentAndCannotCrossReconnect(
	) async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.server.interactions["integer:42"] != nil && fixture.isPaused
		}
		let blocked = try fixture.server.send([
			"method": "fixture/blocker",
			"params": ["text": String(
				repeating: "x",
				count: 1_048_576
			)],
		])
		try await waitUntil
		{
			blocked.hasIncompleteFrame
		}
		try fixture.server.respond(
			to: "integer:42",
			with: .approval(.accept)
		)
		let answer = try #require(fixture.server.pendingInteractionWrites["integer:42"])
		#expect(fixture.server.interactions["integer:42"] != nil)
		#expect(!fixture.server.answeredInteractions.contains("integer:42"))
		#expect(!answer.mayHaveBeenSent)
		#expect(fixture.server.responseMayHaveBeenSent(to: "integer:42") == false)
		#expect(throws: AppServerError.self)
		{
			try fixture.server.respond(
				to: "integer:42",
				with: .approval(.accept)
			)
		}
		let oldGeneration = fixture.server.connectionGeneration
		fixture.server.disconnect()
		do
		{
			try await answer.wait()
			Issue.record("An old connection acknowledged a queued approval.")
		}
		catch let failure as ProtocolWriteFailure
		{
			#expect(!failure.mayHaveBeenSent)
		}
		try fixture.release()
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.server.interactions["integer:42"] != nil
		}
		#expect(fixture.server.connectionGeneration != oldGeneration)
		#expect(fixture.server.pendingInteractionWrites["integer:42"] == nil)
		#expect(!fixture.server.answeredInteractions.contains("integer:42"))
		#expect(fixture.server.responseMayHaveBeenSent(to: "integer:42") == false)
		try await fixture.server.respondAndWait(
			to: "integer:42",
			with: .approval(.accept)
		)
		#expect(fixture.server.answeredInteractions.contains("integer:42"))
		#expect(fixture.server.pendingInteractionWrites["integer:42"] == nil)
		#expect(fixture.server.responseMayHaveBeenSent(to: "integer:42") == true)
		try await waitUntil
		{
			fixture.methods().contains("approval")
		}
		#expect(fixture.methods().filter
		{
			$0 == "approval"
		}.count == 1)
	}

	@Test func queuedRequestCancellationStopsWritingBeforeMainActorCleanup() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.isPaused
		}
		let blocker = try fixture.server.send([
			"method": "fixture/blocker",
			"params": ["text": String(
				repeating: "x",
				count: 1_048_576
			)],
		])
		try await waitUntil
		{
			blocker.hasIncompleteFrame
		}
		var requestStarted = false
		let request = Task
		{
			requestStarted = true
			_ = try await fixture.server.request(
				"fixture/mustNotSend",
				params: [:]
			)
		}
		try await waitUntil
		{
			requestStarted
		}

		request.cancel()
		try drainWritesBeforeMainActorCleanup(fixture)
		#expect(!fixture.methods().contains("fixture/mustNotSend"))

		do
		{
			_ = try await request.value
			Issue.record("The cancelled request unexpectedly completed.")
		}
		catch let failure as ProtocolWriteFailure
		{
			#expect(failure.cause is CancellationError)
			#expect(!failure.mayHaveBeenSent)
			#expect(!failure.requiresDisconnect)
		}
		try await blocker.wait()
	}

	@Test func resolvedInteractionStopsQueuedResponseBeforePublishingEvent() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.server.onEvent = nil
			fixture.close()
		}
		try await fixture.server.connect()
		try await waitUntil
		{
			fixture.server.interactions["integer:42"] != nil && fixture.isPaused
		}
		let blocker = try fixture.server.send([
			"method": "fixture/blocker",
			"params": ["text": String(
				repeating: "x",
				count: 1_048_576
			)],
		])
		try await waitUntil
		{
			blocker.hasIncompleteFrame
		}
		try fixture.server.respond(
			to: "integer:42",
			with: .approval(.accept)
		)
		let response = try #require(fixture.server.pendingInteractionWrites["integer:42"])
		var resolutionPublished = false
		fixture.server.onEvent =
		{
			if case .interactionResolved = $0
			{
				resolutionPublished = true
				do
				{
					try drainWritesBeforeMainActorCleanup(fixture)
				}
				catch
				{
					Issue.record("The writer queue could not drain: \(error)")
				}
			}
		}
		fixture.server.receiveNotification(
			method: "serverRequest/resolved",
			parameters: ["requestId": 42, "threadId": "thread"]
		)
		#expect(resolutionPublished)
		#expect(fixture.server.interactions["integer:42"] == nil)
		#expect(fixture.server.pendingInteractionWrites["integer:42"] == nil)
		#expect(!fixture.methods().contains("approval"))

		do
		{
			try await response.wait()
			Issue.record("The resolved request's queued response unexpectedly reached the pipe.")
		}
		catch let failure as ProtocolWriteFailure
		{
			#expect(!failure.mayHaveBeenSent)
			#expect(!failure.requiresDisconnect)
		}
		try await blocker.wait()
	}

	@Test func historyPagePreservesCursorRequestOrderAndUnicodeContent() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		let page = try await fixture.server.loadTurns(
			threadId: "thread",
			cursor: "older-cursor"
		)
		#expect(page.turns.map(\.id) == ["earlier", "latest"])
		#expect(page.nextCursor == "next-cursor")
		let text = try #require(page.turns.last?.items.first?.text)
		#expect(text.utf8.elementsEqual("é e\u{0301}🧪\u{2028}終\nsecond".utf8))
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["threadId"] as? String == "thread")
		#expect(params["cursor"] as? String == "older-cursor")
		#expect(params["limit"] as? Int == 25)
		#expect(params["sortDirection"] as? String == "desc")
		#expect(params["itemsView"] as? String == "full")
	}

	@Test func initialHistoryPageLoadsTwentyFiveFullTurns() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		_ = try await fixture.server.loadTurns(threadId: "thread")
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["limit"] as? Int == 25)
		#expect(params["cursor"] == nil)
		#expect(params["itemsView"] as? String == "full")
	}

	@Test func turnReferencePageOmitsContentAndCoversTheRailViewport() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		let service: any CodexService = fixture.server
		_ = try await service.loadTurnReferences(
			threadId: "thread",
			cursor: nil
		)
		let request = try #require(fixture.messages().first
		{
			$0["method"] as? String == "thread/turns/list"
		})
		let params = try #require(request["params"] as? [String: Any])
		#expect(params["limit"] as? Int == 100)
		#expect(params["cursor"] == nil)
		#expect(params["sortDirection"] as? String == "desc")
		#expect(params["itemsView"] as? String == "notLoaded")
	}

	@Test func hoverPreviewReadsOnlyBoundaryPagesAndMarksPartialContent() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		let service: any CodexService = fixture.server
		let turn = try await service.loadTurnPreviewContents(
			threadId: "thread",
			reference: ConversationTurnReference(
				id: "picked",
				status: "completed"
			)
		)
		#expect(!turn.itemsAreComplete)
		#expect(turn.items.map(\.id) == ["request", "reply"])
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/items/list"
		}
		#expect(requests.count == 2)
		let parameters = try requests.map
		{
			try #require($0["params"] as? [String: Any])
		}
		#expect(parameters.compactMap
		{
			$0["sortDirection"] as? String
		} == ["asc", "desc"])
		#expect(parameters
			.allSatisfy
			{
				$0["cursor"] == nil && $0["turnId"] as? String == "picked"
			})
	}

	@Test func loadingAReferencedTurnFetchesOnlyItsItemsAndContinuesItsCursor() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		let turn = try await fixture.server.loadTurnContents(
			threadId: "thread",
			reference: ConversationTurnReference(
				id: "picked",
				status: "completed"
			)
		)
		#expect(turn.id == "picked")
		#expect(turn.items.map(\.id) == ["request", "reply"])
		let requests = fixture.messages().filter
		{
			$0["method"] as? String == "thread/items/list"
		}
		#expect(requests.count == 2)
		let parameters = try requests.map
		{
			try #require($0["params"] as? [String: Any])
		}
		#expect(parameters
			.allSatisfy
			{
				$0["threadId"] as? String == "thread" && $0["turnId"] as? String == "picked" &&
					$0["sortDirection"] as? String == "asc"
			})
		#expect(parameters.first?["cursor"] == nil)
		#expect(parameters.last?["cursor"] as? String == "next-items")
		#expect(!fixture.methods().contains("thread/turns/list"))
	}

	@Test func loadingAReferenceRejectsItemsFromAnotherTurn() async throws
	{
		let fixture = try fixture()
		defer
		{
			fixture.close()
		}
		try fixture.release()
		try await fixture.server.connect()
		do
		{
			_ = try await fixture.server.loadTurnContents(
				threadId: "thread",
				reference: ConversationTurnReference(
					id: "foreign",
					status: "completed"
				)
			)
			Issue.record("An item from another turn was accepted")
		}
		catch AppServerError.protocolError
		{
		}
	}

	private func drainWritesBeforeMainActorCleanup(_ fixture: PausedProtocolWriterFixture) throws
	{
		try fixture.release()
		_ = try fixture.server.send(["method": "fixture/queueDrained"])
		let drainedPath = fixture.directory.appendingPathComponent("drained")
		let drained = DispatchSemaphore(value: 0)
		DispatchQueue.global().async
		{
			let deadline = Date().addingTimeInterval(3)
			while !FileManager.default.fileExists(atPath: drainedPath.path), Date() < deadline
			{
				Thread.sleep(forTimeInterval: 0.001)
			}
			drained.signal()
		}
		// Keep actor cleanup pending until the writer has processed the cancelled queue entry.
		#expect(drained.wait(timeout: .now() + 4) == .success)
		#expect(FileManager.default.fileExists(atPath: drainedPath.path))
	}

	private func waitUntil(_ predicate: () -> Bool) async throws
	{
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(3))
		while !predicate(), clock.now < deadline
		{
			try await Task.sleep(for: .milliseconds(1))
		}
		try #require(predicate())
	}

	private func fixture(timeout: Duration = .seconds(3)) throws -> PausedProtocolWriterFixture
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
		import time

		if '--version' in sys.argv:
		    print('codex-cli 0.153.2')
		    sys.exit(0)

		directory = pathlib.Path(__file__).parent
		def send(value):
		    print(json.dumps(value, ensure_ascii=False), flush=True)

		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    with open(directory / 'messages.jsonl', 'a') as log:
		        log.write(json.dumps(message) + '\\n')
		    if method == 'initialize':
		        send({'id': message['id'], 'result': {}})
		    elif method == 'initialized':
		        send({'id': 42, 'method': 'item/commandExecution/requestApproval', 'params': {
		            'threadId': 'thread', 'turnId': 'turn', 'itemId': 'command',
		            'availableDecisions': ['accept', 'decline']
		        }})
		        (directory / 'paused').touch()
		        while not (directory / 'release').exists():
		            time.sleep(0.005)
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
		    elif method == 'fixture/queueDrained':
		        (directory / 'drained').touch()
		    elif method != 'fixture/blocker' and 'id' in message and method:
		        send({'id': message['id'], 'result': {'method': method}})
		""".write(
			to: executable,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: executable.path
		)
		return PausedProtocolWriterFixture(
			server: AppServer(
				executableOverride: executable,
				requestTimeout: timeout
			),
			directory: directory
		)
	}
}

@MainActor
private struct PausedProtocolWriterFixture
{
	let server: AppServer
	let directory: URL

	var isPaused: Bool
	{
		FileManager.default.fileExists(atPath: directory.appendingPathComponent("paused").path)
	}

	func release() throws
	{
		try Data().write(to: directory.appendingPathComponent("release"))
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
			$0["method"] as? String ?? ($0["id"] as? Int == 42 ? "approval" : nil)
		}
	}

	func close()
	{
		server.disconnect()
		try? FileManager.default.removeItem(at: directory)
	}
}
