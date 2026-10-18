import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationSourceActivityTests
{
	@Test func structuredResultWinsOverContentFallback() throws
	{
		let source = try #require(ConversationSourceActivity(json: [
			"id": "structured-result",
			"type": "mcpToolCall",
			"result": [
				"structuredContent": ["winner": "structured"],
				"content": [["type": "text", "text": "Older text fallback"]]
			]
		]))
		#expect(source.displayLanguage == "json")
		let parsed = try #require(JSONSerialization.jsonObject(
			with: Data(source.displayPayload.utf8)
		) as? [String: String])
		#expect(parsed == ["winner": "structured"])
	}

	@Test func explicitErrorWinsOverResultAndExtractsNestedMessage() throws
	{
		let source = try #require(ConversationSourceActivity(json: [
			"id": "failed-result",
			"type": "mcpToolCall",
			"status": "failed",
			"error": "{\"error\":{\"message\":\"Access denied\"}}",
			"result": [
				"structuredContent": ["message": "Stale structured message"],
				"content": [["text": "Stale content message"]]
			]
		]))
		#expect(source.displayIsError)
		#expect(source.displayLanguage == "text")
		#expect(source.displayPayload == "Access denied")
		#expect(source.detail.contains("Stale structured message"))
	}

	@Test func resultErrorContentWinsOverStructuredContentAndUsesTextLanguage() throws
	{
		let source = try #require(ConversationSourceActivity(json: [
			"id": "content-error",
			"type": "mcpToolCall",
			"result": [
				"isError": true,
				"structuredContent": ["message": "Structured fallback"],
				"content": [["text": "{\"message\":\"First failure\"}"],
							["text": "Second failure"]]
			]
		]))
		#expect(source.displayIsError)
		#expect(source.displayLanguage == "text")
		#expect(source.displayPayload == "First failure\n\nSecond failure")
	}
	@Test func emptyErrorContentFallsBackToStructuredMessage() throws
	{
		let contents: [[[String: Any]]] = [[], [["type": "text", "text": "  "]]]
		for content in contents
		{
			let source = try #require(ConversationSourceActivity(json: [
				"id": "empty-content-error",
				"type": "mcpToolCall",
				"error": "",
				"result": [
					"isError": true,
					"content": content,
					"structuredContent": ["message": "Access denied"]
				]
			]))
			#expect(source.displayIsError)
			#expect(source.displayPayload == "Access denied")
			#expect(source.displayLanguage == "text")
		}
	}

	@Test func emptyStructuredResultFallsBackToRecordedContent() throws
	{
		let source = try #require(ConversationSourceActivity(json: [
			"id": "empty-structured",
			"type": "mcpToolCall",
			"result": [
				"structuredContent": [:],
				"content": [["type": "resource", "resource": [
					"uri": "file:///result.txt",
					"text": "Recorded resource result"
				]]]
			]
		]))
		#expect(source.displayPayload.contains("Recorded resource result"))
		#expect(source.displayPayload.contains("file:///result.txt"))
	}

}
