import AppKit

/// Colors Markdown source ranges without changing bytes, selection, or undo history.
@MainActor
enum MarkdownSourceStyling
{
	private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}(?:[ \t]+|$)"#)
	private static let list =
		try! NSRegularExpression(pattern: #"^ {0,3}(?:[-+*]|[0-9]+[.)])(?=[ \t])"#)
	private static let strong = try! NSRegularExpression(
		pattern: #"(?<!\\)(?:\*\*[^*\r\n]+\*\*|__[^_\r\n]+__)"#
	)
	private static let asteriskEmphasis = try! NSRegularExpression(
		pattern: #"(?<!\\)(?<!\*)\*(?!\*)[^*\r\n]+(?<!\\)\*(?!\*)"#
	)
	private static let underscoreEmphasis = try! NSRegularExpression(
		pattern: #"(?<!\\)(?<!_)_(?!_)[^_\r\n]+(?<!\\)_(?!_)"#
	)
	private static let inlineCode = try! NSRegularExpression(pattern: #"(?<!\\)`+[^`\r\n]+`+"#)
	private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)

	static func apply(
		to storage: NSMutableAttributedString,
		source: String,
		dark: Bool
	)
	{
		let red = SyntaxColorTokens.color(
			"keyword",
			dark: dark
		)
		let green = SyntaxColorTokens.color(
			"string",
			dark: dark
		)
		let orange = SyntaxColorTokens.color(
			"number",
			dark: dark
		)
		let nsSource = source as NSString
		var activeFence: (character: Character, count: Int)?
		nsSource.enumerateSubstrings(
			in: NSRange(
				location: 0,
				length: nsSource.length
			),
			options: .byLines
		)
		{
			_, lineRange, _, _ in
			let line = nsSource.substring(with: lineRange)
			let local = NSRange(
				location: 0,
				length: lineRange.length
			)
			if let marker = fence.firstMatch(
				in: line,
				range: local
			)
			{
				let delimiter = (line as NSString).substring(with: marker.range(at: 1))
				let character = delimiter.first ?? "`"
				if let currentFence = activeFence
				{
					if character == currentFence.character && delimiter.count >= currentFence.count
					{
						activeFence = nil
					}
				}
				else
				{
					activeFence = (character, delimiter.count)
				}
				return
			}
			guard activeFence == nil
			else
			{
				return
			}
			if heading.firstMatch(
				in: line,
				range: local
			) != nil
			{
				storage.addAttribute(
					.foregroundColor,
					value: red,
					range: lineRange
				)
			}
			if let marker = list.firstMatch(
				in: line,
				range: local
			)
			{
				let value = (line as NSString).substring(with: marker.range)
				let leading = value.utf16.prefix(while:
					{
						$0 == 32
					}).count
				let range = NSRange(
					location: lineRange.location + marker.range.location + leading,
					length: marker.range.length - leading
				)
				storage.addAttribute(
					.foregroundColor,
					value: red,
					range: range
				)
			}
			apply(
				strong,
				color: orange,
				line: line,
				lineRange: lineRange,
				to: storage
			)
			apply(
				asteriskEmphasis,
				color: orange,
				line: line,
				lineRange: lineRange,
				to: storage
			)
			apply(
				underscoreEmphasis,
				color: orange,
				line: line,
				lineRange: lineRange,
				to: storage
			)
			apply(
				inlineCode,
				color: green,
				line: line,
				lineRange: lineRange,
				to: storage
			)
		}
	}

	private static func apply(
		_ expression: NSRegularExpression,
		color: NSColor,
		line: String,
		lineRange: NSRange,
		to storage: NSMutableAttributedString
	)
	{
		for match in expression.matches(
			in: line,
			range: NSRange(
				location: 0,
				length: lineRange.length
			)
		)
		{
			storage.addAttribute(
				.foregroundColor,
				value: color,
				range: NSRange(
					location: lineRange.location + match.range.location,
					length: match.range.length
				)
			)
		}
	}

}
