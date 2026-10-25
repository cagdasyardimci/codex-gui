import Testing

@testable import CodexGUI

struct MarkdownFileMetadataTests
{

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
