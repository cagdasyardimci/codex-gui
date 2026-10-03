import Testing

@testable import CodexGUI

struct CodePreviewPresentationTests
{
	@Test func emptyAndTrailingNewlineRetainEditableDocumentLineSemantics()
	{
		let empty = CodePreviewPresentation(
			text: "",
			relativePath: "empty.txt"
		)
		#expect(empty.lineStarts == [0])
		#expect(empty.lineNumber(atUTF16Offset: 0) == 1)
		let trailing = CodePreviewPresentation(
			text: "first\nsecond\n",
			relativePath: "a.swift"
		)
		#expect(trailing.lineStarts == [0, 6, 13])
		#expect(trailing.lineNumber(atUTF16Offset: 13) == 3)
	}

	@Test func mixedLineEndingsPreserveExactSourceAndCountCRLFOnce()
	{
		let source = "a\r\nb\rc\nd\u{2028}e\u{2029}"
		let presentation = CodePreviewPresentation(
			text: source,
			relativePath: "text.txt"
		)
		#expect(presentation.text == source)
		#expect(presentation.lineStarts == [0, 3, 5, 7, 9, 11])
		#expect(presentation.lineNumber(atUTF16Offset: 2) == 1)
		#expect(presentation.lineNumber(atUTF16Offset: 3) == 2)
	}

	@Test func unicodeAndWrappedFragmentOffsetsUseLogicalUTF16Lines()
	{
		let presentation = CodePreviewPresentation(
			text: "🧭abc\nnext",
			relativePath: "a.swift"
		)
		#expect(presentation.lineStarts == [0, 6])
		#expect(presentation.utf16Length == 10)
		#expect(presentation.lineNumber(atUTF16Offset: 0) == 1)
		#expect(presentation.lineNumber(atUTF16Offset: 4) == 1)
		#expect(presentation.lineNumber(atUTF16Offset: 6) == 2)
		#expect(presentation.lineNumber(atUTF16Offset: -1) == 1)
		#expect(presentation.lineNumber(atUTF16Offset: 100) == 2)
	}

	@Test func syntaxSelectionUsesCaseInsensitiveExtensionAndUnknownFilesRemainPlain()
	{
		#expect(CodePreviewPresentation(
			text: "let x = 1",
			relativePath: "Sources/A.SWIFT"
		)
		.language == "swift")
		#expect(CodePreviewPresentation(
			text: "",
			relativePath: "a.tsx"
		).language == "typescript")
		#expect(CodePreviewPresentation(
			text: "",
			relativePath: "README"
		).language == nil)
		#expect(CodePreviewPresentation(
			text: "",
			relativePath: "file.unknown"
		).language == nil)
	}
}
