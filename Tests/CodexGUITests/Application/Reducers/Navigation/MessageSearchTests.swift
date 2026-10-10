import Foundation
import Testing

@testable import CodexGUI

@Suite
struct MessageSearchTests
{
	@Test(arguments: [0, 1, 2, 3, 4])
	func matchingFieldsKeepTheirPrecedence(firstMatchingField: Int) throws
	{
		let texts = ["needle text", "needle command", "needle output"]
		let keys = ["text", "command", "aggregatedOutput"]
		var json: [String: Any] = ["id": "item", "type": "agentMessage"]
		for index in keys.indices
		{
			json[keys[index]] = index < firstMatchingField ? "unrelated" : texts[index]
		}
		json["changes"] = [
			["path": firstMatchingField > 3 ? "unrelated.swift" : "needle-first.swift"],
			["path": "needle-second.swift"],
		]
		let item = try #require(CodexItem(json: json))
		let results = search(
			items: [item],
			query: "needle"
		)
		let expected = texts + ["needle-first.swift", "needle-second.swift"]
		#expect(results.hits.count == 1)
		#expect(results.hits.first?.snippet == expected[firstMatchingField])
	}

	@Test func snippetsKeepExactUnicodeAndCharacterContext() throws
	{
		let grapheme = "👩🏽‍💻"
		let accented = "CaFe\u{301}"
		let text = String(
			repeating: grapheme,
			count: 70
		) + accented + "\n"
			+ String(
				repeating: "界",
				count: 130
			)
		let item = try #require(CodexItem(json: [
			"id": "unicode",
			"type": "agentMessage",
			"text": text,
		]))
		let results = search(
			items: [item],
			query: " café "
		)
		let snippet = try #require(results.hits.first?.snippet)
		let expected = "…" + String(
			repeating: grapheme,
			count: 60
		) + accented + " "
			+ String(
				repeating: "界",
				count: 99
			) + "…"
		#expect(results.query == "café")
		#expect(snippet.utf8.elementsEqual(expected.utf8))
	}

	@Test func missingAndEmptyFieldsFallThroughToFirstMatchingPath() throws
	{
		let item = try #require(CodexItem(json: [
			"id": "path",
			"type": "fileChange",
			"text": "",
			"aggregatedOutput": "",
			"changes": [
				["path": "unrelated.swift"],
				["path": "folder/Café.swift"],
				["path": "later/cafe.swift"],
			],
		]))
		let results = search(
			items: [item],
			query: "cafe"
		)
		#expect(results.hits.map(\.snippet) == ["folder/Café.swift"])
	}

	private func search(
		items: [CodexItem],
		query: String
	) -> MessageSearchResults
	{
		MessageSearch.search(
			query: query,
			threads: [SearchableThread(
				threadID: "thread",
				title: "Thread",
				turns: [CodexTurn(
					id: "turn",
					status: "completed",
					items: items,
					error: nil
				)],
				hasEarlierTurns: false
			)],
			totalThreadCount: 1
		)
	}
}
