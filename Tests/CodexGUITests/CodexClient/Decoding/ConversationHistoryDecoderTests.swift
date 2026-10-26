import Foundation
import Testing
@testable import CodexGUI

@Suite
struct ConversationHistoryDecoderTests
{

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

}
