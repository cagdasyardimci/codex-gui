import Foundation
import Testing
@testable import CodexGUI

@Suite
struct ConversationHistoryDecoderTests
{
	@Test func fullPageMatchesLegacyConversionIncludingMalformedItemsAndExactText() throws
	{
		let text = "é e\u{0301}🧪\u{2028}終"
		let turns: [[String: Any]] = [
			["id": "latest",
				"status": "completed",
				"startedAt": 10.25,
				"completedAt": 15.5,
				"durationMs": 5250.0,
				"error": ["message": "fixture"],
				"items": [
				["id": "user", "type": "userMessage", "content": [
					["type": "text", "text": text],
					["type": "mention", "path": "/tmp/a.swift", "name": "a.swift"],
					["type": "localImage", "path": "/tmp/image.png"],
					["type": "text", "text": "second\nline"],
				]],
				["type": "agentMessage", "text": "missing ID"],
				["id": "command",
					"type": "commandExecution",
					"command": "cat a.swift",
					"aggregatedOutput": text,
					"exitCode": 0,
					"durationMs": 1.5],
				["id": "answer", "type": "agentMessage", "text": text],
				]],
			["status": "completed", "items": [["id": "ignored", "type": "agentMessage"]]],
			["id": "earlier", "items": "invalid array"],
		]
		let page = try ConversationHistoryDecoder.decode(ProtocolJSONPayload(value: [
			"data": turns,
			"nextCursor": "older\u{2028}cursor",
		]))
		let legacyDecodedTurns = turns.compactMap(CodexTurn.init(json:))
		let legacy = Array(legacyDecodedTurns.reversed())
		#expect(page.turns.map(\.id) == ["earlier", "latest"])
		#expect(page.nextCursor == "older\u{2028}cursor")
		let earlier = try #require(page.turns.first)
		#expect(earlier.status == "inProgress")
		#expect(earlier.error == nil)
		#expect(earlier.startedAt == nil)
		#expect(earlier.completedAt == nil)
		#expect(earlier.durationMs == nil)
		#expect(earlier.items.isEmpty)
		#expect(earlier.itemsAreComplete)
		let latest = try #require(page.turns.last)
		#expect(latest.status == "completed")
		#expect(latest.error == "fixture")
		#expect(latest.startedAt == Date(timeIntervalSince1970: 10.25))
		#expect(latest.completedAt == Date(timeIntervalSince1970: 15.5))
		#expect(latest.durationMs == 5250.0)
		#expect(latest.itemsAreComplete)
		#expect(latest.items.map(\.id) == ["user", "command", "answer"])
		#expect(latest.items.map(\.type) == ["userMessage", "commandExecution", "agentMessage"])
		let command = try #require(latest.items.first
		{
			$0.id == "command"
		})
		#expect(command.command == "cat a.swift")
		#expect(command.output?.utf8.elementsEqual(text.utf8) == true)
		#expect(command.exitCode == 0)
		#expect(command.durationMs == 1.5)
		#expect(latest.items.last?.text?.utf8.elementsEqual(text.utf8) == true)
		let references = try #require(latest.items.first?.references)
		#expect(references.map(\.kind) == [.fileReference, .image])
		#expect(references.map(\.path) == ["/tmp/a.swift", "/tmp/image.png"])
		for (actual, expected) in zip(
			page.turns,
			legacy
		)
		{
			#expect(actual.status == expected.status)
			#expect(actual.error == expected.error)
			#expect(actual.startedAt == expected.startedAt)
			#expect(actual.completedAt == expected.completedAt)
			#expect(actual.durationMs == expected.durationMs)
			#expect(actual.items.map(\.id) == expected.items.map(\.id))
			for (item, expectedItem) in zip(
				actual.items,
				expected.items
			)
			{
				#expect(item.type == expectedItem.type)
				if let text = item.text, let expectedText = expectedItem.text
				{
					#expect(text.utf8.elementsEqual(expectedText.utf8))
				}
				else
				{
					#expect(item.text == nil && expectedItem.text == nil)
				}
				#expect(item.references == expectedItem.references)
				#expect(item.command == expectedItem.command)
				if let output = item.output, let expectedOutput = expectedItem.output
				{
					#expect(output.utf8.elementsEqual(expectedOutput.utf8))
				}
				else
				{
					#expect(item.output == nil && expectedItem.output == nil)
				}
				#expect(item.exitCode == expectedItem.exitCode)
				#expect(item.durationMs == expectedItem.durationMs)
			}
		}
		#expect(page.turns.last?.items.first?.text?.utf8
			.elementsEqual((text + "\nsecond\nline").utf8)
			== true)
		#expect(page.turns.last?.items.first?.references.map(\.id) == ["user:1", "user:2"])
	}

	@Test func malformedPageShapesRetainExistingEmptyDefaults() throws
	{
		for value in [[String: Any](), ["data": NSNull(), "nextCursor": 42], ["data": "invalid"]]
		{
			let page = try ConversationHistoryDecoder.decode(ProtocolJSONPayload(value: value))
			#expect(page.turns.isEmpty)
			#expect(page.nextCursor == nil)
		}
	}

	@Test func malformedMetadataUsesDefaultsAndInvalidIDsAreSkipped() throws
	{
		let turns: [[String: Any]] = [
			["id": "malformed",
				"status": 42,
				"error": ["message": 42],
				"startedAt": "10",
				"completedAt": NSNull(),
				"durationMs": "5"],
			["id": 42, "status": "completed"],
			["status": "completed"],
		]
		let page = try ConversationHistoryDecoder.decode(ProtocolJSONPayload(value: [
			"data": turns,
		]))
		#expect(page.turns.map(\.id) == ["malformed"])
		let turn = try #require(page.turns.first)
		#expect(turn.status == "inProgress")
		#expect(turn.error == nil)
		#expect(turn.startedAt == nil)
		#expect(turn.completedAt == nil)
		#expect(turn.durationMs == nil)
		#expect(turn.items.isEmpty)
		#expect(turn.itemsAreComplete)
	}

	@Test func cancellationIsCheckedBetweenItemsOfOneLargeTurn() throws
	{
		let items = (0 ..< 100).map
		{
			["id": "item-\($0)", "type": "agentMessage", "text": "fixture"]
		}
		let payload = ProtocolJSONPayload(value: ["data": [["id": "turn", "items": items]]])
		var checks = 0
		#expect(throws: CancellationError.self)
		{
			try ConversationHistoryDecoder.decode(
				payload,
				isCancelled:
				{
					checks += 1
					return checks == 5
				}
			)
		}
		#expect(checks == 5)
	}

	@MainActor
	@Test func backgroundDecodingLeavesMainActorAvailable() async throws
	{
		let payload = ProtocolJSONPayload(value: ["data": (0 ..< 50).map
			{
				["id": "turn-\($0)",
					"items": (0 ..< 100).map
					{
					["id": "item-\($0)", "type": "agentMessage", "text": "fixture"]
					}]
			}])
		let decoding = Task.detached
		{
			var checkpointWasOffMainThread: [Bool] = []
			let page = try ConversationHistoryDecoder.decode(
				payload,
				isCancelled:
				{
					checkpointWasOffMainThread.append(!Thread.isMainThread)
					return Task.isCancelled
				}
			)
			return (page, checkpointWasOffMainThread)
		}
		defer
		{
			decoding.cancel()
		}
		var mainActorAdvanced = false
		await Task
		{
			mainActorAdvanced = true
		}.value
		#expect(mainActorAdvanced)
		let (page, checkpointWasOffMainThread) = try await withTaskCancellationHandler
		{
			try await decoding.value
		} onCancel:
		{
			decoding.cancel()
		}
		// Detached tasks do not inherit the test's assertion context. Record every decoder
		// checkpoint in the worker and assert in the awaiting test for correct attribution.
		let expectedCheckpointCount = 50 * (100 + 1) + 1
		#expect(checkpointWasOffMainThread.count == expectedCheckpointCount)
		for wasOffMainThread in checkpointWasOffMainThread
		{
			#expect(wasOffMainThread)
		}
		#expect(page.turns.count == 50)
		for turn in page.turns
		{
			#expect(turn.items.count == 100)
		}
	}
}
