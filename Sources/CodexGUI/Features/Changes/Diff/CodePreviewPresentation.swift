import Foundation

/// Keeps source offsets in UTF-16, matching AppKit's text and layout ranges.
struct CodePreviewPresentation: Equatable, Sendable
{
	let text: String
	let relativePath: String
	let language: String?
	let lineStarts: [Int]
	let utf16Length: Int

	init(
		text: String,
		relativePath: String
	)
	{
		self.text = text
		self.relativePath = relativePath
		language = Self.language(for: relativePath)
		let utf16Units = Array(text.utf16)
		utf16Length = utf16Units.count
		lineStarts = Self.logicalLineStarts(in: utf16Units)
	}

	private static func logicalLineStarts(in utf16Units: [UInt16]) -> [Int]
	{
		var logicalLineStarts = [0]
		var offset = 0
		while offset < utf16Units.count
		{
			let codeUnit = utf16Units[offset]
			offset += 1
			if codeUnit == 13, offset < utf16Units.count, utf16Units[offset] == 10
			{
				offset += 1
			}
			let isLineEnding =
				codeUnit == 10 || codeUnit == 13 || codeUnit == 0x2028 || codeUnit == 0x2029
			if isLineEnding
			{
				logicalLineStarts.append(offset)
			}
		}
		return logicalLineStarts
	}

	var lineCount: Int
	{
		lineStarts.count
	}

	/// Wrapped visual fragments retain the logical source line's number.
	func lineNumber(atUTF16Offset offset: Int) -> Int
	{
		let boundedOffset = min(
			max(
				0,
				offset
			),
			utf16Length
		)
		var lower = 0
		var upper = lineStarts.count
		while lower < upper
		{
			let middle = (lower + upper) / 2
			if lineStarts[middle] <= boundedOffset
			{
				lower = middle + 1
			}
			else
			{
				upper = middle
			}
		}
		return lower
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
