import AppKit
import Highlighter

/// Uses bundled Highlight.js through JavaScriptCore; native text remains the source of truth.
@MainActor
enum CodeSyntaxHighlighter
{
	private static let maximumSourceLength = 24_000
	private static var lightHighlighter: Highlighter?
	private static var darkHighlighter: Highlighter?
	private static var attemptedInitialization = false
	private struct CacheKey: Hashable
	{
		// String equality normalizes Unicode; code and copy text retain exact bytes.
		let sourceBytes: Data
		let language: String
		let dark: Bool
	}
	private struct CachedHighlight
	{
		let colors: NSAttributedString
		let estimatedBytes: Int
		var lastUse: Int
	}
	private static var cachedHighlights: [CacheKey: CachedHighlight] = [:]
	private static var cachedBytes = 0
	private static var cacheClock = 0
	private static let cacheCapacity = 64
	private static let cacheByteCapacity = 2 * 1024 * 1024
	private static let estimatedColorRunBytes = 128

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
		let key = CacheKey(
			sourceBytes: Data(source.utf8),
			language: language,
			dark: dark
		)
		cacheClock += 1
		if var cached = cachedHighlights[key]
		{
			cached.lastUse = cacheClock
			cachedHighlights[key] = cached
			return cached.colors
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

		let attributes = colorAttributes(
			from: highlighted,
			source: source
		)
		// Include native color-run overhead so dense code cannot bypass the byte bound.
		let estimatedTextBytes = key.sourceBytes.count + attributes.text.length * 2
		let colorRunBytes = attributes.runCount * estimatedColorRunBytes
		cache(
			attributes.text,
			for: key,
			estimatedBytes: estimatedTextBytes + colorRunBytes
		)
		return attributes.text
	}

	private static func colorAttributes(
		from highlighted: NSAttributedString,
		source: String
	) -> (text: NSAttributedString, runCount: Int)
	{
		// Paragraph, font, copy ranges and backgrounds belong to the native Markdown renderer.
		let colors = NSMutableAttributedString(string: source)
		var runCount = 0
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
				runCount += 1
				colors.addAttribute(
					.foregroundColor,
					value: color,
					range: range
				)
			}
		}
		return (NSAttributedString(attributedString: colors), runCount)
	}

	private static func cache(
		_ colors: NSAttributedString,
		for key: CacheKey,
		estimatedBytes: Int
	)
	{
		guard estimatedBytes <= cacheByteCapacity
		else
		{
			return
		}
		while cachedHighlights.count >= cacheCapacity
			|| cachedBytes + estimatedBytes > cacheByteCapacity
		{
			guard let oldest = cachedHighlights.min(by:
				{
					$0.value.lastUse < $1.value.lastUse
				})
			else
			{
				return
			}
			cachedBytes -= oldest.value.estimatedBytes
			cachedHighlights.removeValue(forKey: oldest.key)
		}
		cachedHighlights[key] = CachedHighlight(
			colors: colors,
			estimatedBytes: estimatedBytes,
			lastUse: cacheClock
		)
		cachedBytes += estimatedBytes
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
