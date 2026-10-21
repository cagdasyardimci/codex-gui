import Testing

@testable import CodexGUI

struct MarkdownFileMetadataTests
{
	@Test func extractsOrderedScalarsAndTagSequencesWithoutChangingBody() throws
	{
		let body = "\r\n# Heading\r\n\r\n[Link](guide.md)\r\n"
		let source = "---\r\ntitle: 'A title: it''s quoted'\r\n" +
			"description: Plain description # comment\r\n" +
			"tags: [markdown, \"two words\", 'comma, inside'] # tags\r\n---\r\n" + body
		let metadata = try #require(MarkdownFileMetadata.parse(source))
		#expect(metadata.body == body)
		#expect(metadata.entries == [
			.entry(
				"title",
				["A title: it's quoted"]
			),
			.entry(
				"description",
				["Plain description"]
			),
			.entry(
				"tags",
				["markdown", "two words", "comma, inside"],
				sequence: true
			)
		])
	}

	@Test func supportsBlockSequencesEmptyValuesAndJSONEscapedScalars() throws
	{
		let source = """
		---
		title: "An escaped \\\"title\\\""
		tags:
		  - first
		  - 'second item'
		empty:
		count: 42
		---
		Body
		"""
		let metadata = try #require(MarkdownFileMetadata.parse(source))
		#expect(metadata.entries.map(\.key) == ["title", "tags", "empty", "count"])
		#expect(metadata.entries[0].values == ["An escaped \"title\""])
		#expect(metadata.entries[1].values == ["first", "second item"])
		#expect(metadata.entries[1].isSequence)
		#expect(metadata.entries[2].values == [""])
		#expect(metadata.body == "Body")
	}

	@Test(arguments: [
		"---\ntitle: Unclosed\n# Body",
		"---\ntitle: \"Unclosed\n---\n# Body",
		"---\ntags: [one, two\n---\n# Body",
		"---\ntags: [one # comment, two]\n---\n# Body",
		"---\ntitle: duplicate\ntitle: value\n---\n# Body",
		"---\nparent:\n  child: value\n---\n# Body",
		"---\ntags:\n  - first\n    - nested\n---\n# Body",
		"---\ntitle: &anchor value\n---\n# Body",
		"---\ntitle: *anchor\n---\n# Body",
		"---\ntitle: !!str value\n---\n# Body",
		"---\ntitle: |\n  paragraph\n---\n# Body",
		"---\ntags: [[nested], one]\n---\n# Body",
		"---\ntitle:\tvalue\n---\n# Body",
		"\n---\ntitle: Later delimiter\n---\n# Body",
		"# Heading\n---\nBody"
	])
	func unsupportedOrMalformedFrontmatterRemainsLiteral(_ source: String)
	{
		#expect(MarkdownFileMetadata.parse(source) == nil)
	}

	@Test func oversizedFrontmatterIsNotRemoved()
	{
		let source = "---\ntitle: " + String(
			repeating: "a",
			count: 65_536
		) + "\n---\nBody"
		#expect(MarkdownFileMetadata.parse(source) == nil)
	}
}

private extension MarkdownFileMetadata.Entry
{
	static func entry(
		_ key: String,
		_ values: [String],
		sequence: Bool = false
	) -> Self
	{
		Self(
			key: key,
			values: values,
			isSequence: sequence
		)
	}
}
