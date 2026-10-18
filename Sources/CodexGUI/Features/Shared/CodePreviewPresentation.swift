import Foundation

/// Keeps source offsets in UTF-16, matching AppKit's text and layout ranges.
struct CodePreviewPresentation: Equatable, Sendable
{
	let text: String
	let relativePath: String
	let language: String?
	private let sourceLines: SourceLineIndex
	var lineStarts: [Int]
	{
		sourceLines.lineStarts
	}
	var utf16Length: Int
	{
		sourceLines.utf16Length
	}

	init(
		text: String,
		relativePath: String
	)
	{
		self.text = text
		self.relativePath = relativePath
		language = Self.language(for: relativePath)
		sourceLines = SourceLineIndex(text)
	}

	var lineCount: Int
	{
		lineStarts.count
	}

	/// Wrapped visual fragments retain the logical source line's number.
	func lineNumber(atUTF16Offset offset: Int) -> Int
	{
		sourceLines.lineNumber(atUTF16Offset: offset)
	}

	private static func language(for path: String) -> String?
	{
		let languages = [
			"swift": "swift",
			"js": "javascript",
			"jsx": "javascript",
			"ts": "typescript",
			"tsx": "typescript",
			"py": "python",
			"json": "json",
			"html": "xml",
			"xml": "xml",
			"svg": "xml",
			"css": "css",
			"sh": "bash",
			"zsh": "bash",
			"bash": "bash",
			"yml": "yaml",
			"yaml": "yaml",
			"md": "markdown",
			"c": "c",
			"h": "c",
			"cpp": "cpp",
			"hpp": "cpp",
			"rs": "rust",
			"go": "go",
			"sql": "sql",
			"toml": "toml",
		]
		return languages[(path as NSString).pathExtension.lowercased()]
	}
}
