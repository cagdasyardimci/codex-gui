import Foundation
import Testing

@testable import CodexGUI

@Suite
struct SourceActivityResultPresentationTests
{
	@Test func largeEscapedResultStaysBoundedValidJSON() throws
	{
		let items: [[String: Any]] = (0 ..< 80).map
		{
			["index": $0, "text": String(
				repeating: "quoted \" value ",
				count: 80
			)]
		}
		let payload = SourceActivityResultPresentation.displayValue([
			"schemaVersion": 3,
			"label": "A \"quoted\" label",
			"items": items
		])
		#expect(payload.language == "json")
		#expect(payload.text.count <= 16_384)
		let parsed = try #require(JSONSerialization.jsonObject(
			with: Data(payload.text.utf8)
		) as? [String: Any])
		#expect(parsed["schemaVersion"] as? Int == 3)
		#expect(parsed["label"] as? String == "A \"quoted\" label")
		#expect(((parsed["items"] as? [Any])?.count ?? 0) < items.count)
		#expect(payload.text.contains("Remaining result items omitted"))
		let schema = try #require(payload.text.range(of: "\"schemaVersion\""))
		let array = try #require(payload.text.range(of: "\"items\""))
		#expect(schema.lowerBound < array.lowerBound)
	}
	@Test func recordedResourceLinkAndMediaKindsProduceBoundedReadableContent() throws
	{
		let cases: [([String: Any], String)] = [
			(["type": "resource", "resource": [
				"uri": "file:///Guide.md",
				"mimeType": "text/markdown",
				"text": "Embedded guide"
			]], "Embedded guide"),
			(["type": "resource_link",
				"uri": "https://example.com/guide",
				"name": "Linked guide",
				"mimeType": "text/markdown"], "Linked guide"),
			(["type": "image", "mimeType": "image/png", "data": "AAAA"], "Recorded image data"),
			(["type": "audio", "mimeType": "audio/wav", "data": "AAAA"], "Recorded audio data"),
			(
				["type": "future", "payload": ["label": "Future recorded value"]],
				"Future recorded value"
			),
		]
		for (content, expected) in cases
		{
			let result = SourceActivityResultPresentation.displayContent([content])
			#expect(result.text.contains(expected))
			#expect(result.text.count <= 16_384)
			#expect(result.language == "json")
			#expect((try JSONSerialization
					.jsonObject(with: Data(result.text.utf8))) is [String: Any])
		}
		let media = SourceActivityResultPresentation.displayContent([
			[
				"type": "image",
				"mimeType": "image/png",
				"data": String(
					repeating: "A",
					count: 100_000
				)
			]
		])
		#expect(media.text.contains("100000 encoded bytes"))
		#expect(media.text.count < 500)
	}

	@Test func mixedContentRetainsTextResourceAndUnknownMetadata()
	{
		let result = SourceActivityResultPresentation.displayContent([
			["type": "text", "text": "First result"],
			["type": "resource", "resource": ["uri": "file:///a.txt", "text": "Resource result"]],
			["type": "future", "value": "Recorded metadata"],
		])
		#expect(result.language == "text")
		#expect(result.text.contains("First result"))
		#expect(result.text.contains("Resource result"))
		#expect(result.text.contains("file:///a.txt"))
		#expect(result.text.contains("Recorded metadata"))
	}

	@Test func errorExtractionSkipsEmptyPreferredFields()
	{
		let result = SourceActivityResultPresentation.errorPayload([
			"message": "  ",
			"error": ["message": "Access denied"]
		])
		#expect(result.text == "Access denied")
		#expect(result.language == "text")
	}

	@Test func errorContentStopsAtItsAggregateDisplayBudget()
	{
		let result = SourceActivityResultPresentation.displayContent(
			[
				["type": "text", "text": String(
					repeating: "First failure ",
					count: 2_000
				)],
				["type": "resource", "resource": ["text": "Later failure"]],
			],
			isError: true
		)
		#expect(result.language == "text")
		#expect(result.text.count <= 16_384)
		#expect(result.text.hasPrefix("First failure"))
		#expect(result.text.hasSuffix("[Remaining result content omitted]"))
		#expect(!result.text.contains("Later failure"))
	}

}
