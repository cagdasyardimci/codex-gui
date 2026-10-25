import Testing

@testable import CodexGUI

struct CodePreviewPresentationTests
{

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

}
