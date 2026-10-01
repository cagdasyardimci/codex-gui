import AppKit
import Highlighter

/// Uses bundled Highlight.js through JavaScriptCore; native text remains the source of truth.
@MainActor
enum ConversationCodeHighlighter
{
	private static let maximumSourceLength = 24_000
	private static var lightHighlighter: Highlighter?
	private static var darkHighlighter: Highlighter?
	private static var attemptedInitialization = false

	static func highlightedCode(
		_ source: String,
		language: String?,
		dark: Bool
	) -> NSAttributedString?
	{
		guard !source.isEmpty, source.utf16.count <= maximumSourceLength,
				let language = normalizedLanguage(language)
		else
		{
			return nil
		}
		initializeHighlighters()
		guard let highlighter = dark ? darkHighlighter : lightHighlighter,
				highlighter.supportedLanguages().contains(language),
				let highlighted = highlighter.highlight(
				source,
				as: language,
				doFastRender: true
				), highlighted.string == source
		else
		{
			return nil
		}

		// Paragraph, font, copy ranges and backgrounds belong to the native Markdown renderer.
		let colors = NSMutableAttributedString(string: source)
		highlighted.enumerateAttribute(
			.foregroundColor,
			in: NSRange(
				location: 0,
				length: highlighted.length
			)
		)
		{
			color, range, _ in
			if let color = color as? NSColor
			{
				colors.addAttribute(
					.foregroundColor,
					value: color,
					range: range
				)
			}
		}
		return NSAttributedString(attributedString: colors)
	}

	private static func normalizedLanguage(_ language: String?) -> String?
	{
		guard let token = language?.split(whereSeparator: \.isWhitespace).first
		else
		{
			return nil
		}
		let name = token.lowercased()
		let aliases = [
			"py": "python",
			"python3": "python",
			"js": "javascript",
			"ts": "typescript",
			"sh": "bash",
			"shell": "bash",
			"c++": "cpp",
			"c#": "csharp",
			"yml": "yaml",
		]
		return aliases[name] ?? name
	}

	private static func initializeHighlighters()
	{
		guard !attemptedInitialization
		else
		{
			return
		}
		attemptedInitialization = true
		lightHighlighter = makeHighlighter(theme: "github")
		darkHighlighter = makeHighlighter(theme: "github-dark")
	}

	private static func makeHighlighter(theme: String) -> Highlighter?
	{
		guard let highlighter = Highlighter(), highlighter.setTheme(theme)
		else
		{
			return nil
		}
		return highlighter
	}
}
