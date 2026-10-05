import Testing

@testable import CodexGUI

struct FileChangeTests
{
	@Test(arguments: ["path", "kind", "move_path", "diff"])
	func exactComparisonPreservesUnicodeBytesInEveryField(_ field: String) throws
	{
		let composed = try change(
			text: "\u{00E9}",
			field: field
		)
		let decomposed = try change(
			text: "e\u{0301}",
			field: field
		)
		#expect(composed == decomposed)
		#expect(!FileChange.haveSameExactContent(
			[composed],
			[decomposed]
		))
		#expect(FileChange.haveSameExactContent(
			[composed],
			[composed]
		))
	}

	@Test func exactComparisonPreservesOrderCountAndOptionalRenameMetadata() throws
	{
		let first = try change(
			text: "first",
			field: "path"
		)
		let second = try change(
			text: "second",
			field: "path"
		)
		#expect(!FileChange.haveSameExactContent(
			[first, second],
			[second, first]
		))
		#expect(!FileChange.haveSameExactContent(
			[first],
			[first, second]
		))
		#expect(FileChange.haveSameExactContent(
			[],
			[]
		))
		let withoutRename = try #require(FileChange(json: ["path": "file"]))
		let emptyRename = try #require(FileChange(json: [
			"path": "file",
			"kind": ["type": "unknown", "move_path": ""]
		]))
		#expect(!FileChange.haveSameExactContent(
			[withoutRename],
			[emptyRename]
		))
	}

	private func change(
		text: String,
		field: String
	) throws -> FileChange
	{
		try #require(FileChange(json: [
			"path": field == "path" ? text : "file",
			"kind": [
				"type": field == "kind" ? text : "update",
				"move_path": field == "move_path" ? text : "renamed"
			],
			"diff": field == "diff" ? text : "diff"
		]))
	}
}
