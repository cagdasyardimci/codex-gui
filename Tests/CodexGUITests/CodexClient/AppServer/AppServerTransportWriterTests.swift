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
