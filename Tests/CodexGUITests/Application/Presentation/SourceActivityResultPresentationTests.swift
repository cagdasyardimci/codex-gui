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

}
