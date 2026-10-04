import Foundation
import Testing
@testable import CodexGUI

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
		let legacy = Array(turns.compactMap(CodexTurn.init(json:)).reversed())
		#expect(page.turns.map(\.id) == ["earlier", "latest"])
		#expect(page.nextCursor == "older\u{2028}cursor")
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
			try ConversationHistoryDecoder.decode(
				payload,
				isCancelled:
				{
					#expect(!Thread.isMainThread)
					return Task.isCancelled
				}
			)
		}
		var mainActorAdvanced = false
		await Task
		{
			mainActorAdvanced = true
		}.value
		#expect(mainActorAdvanced)
		#expect(try await decoding.value.turns.count == 50)
	}
}
