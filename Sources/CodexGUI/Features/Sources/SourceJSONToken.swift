import Foundation

/// Identifies JSON color roles without copying the remaining source for every quoted token.
struct SourceJSONToken: Equatable
{
	enum Style: Equatable
	{
		case key, string, literal, number
	}

	let range: NSRange
	let style: Style
	private static let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
	private static let expression = try! NSRegularExpression(
		pattern: #""(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b"#
	)

	static func tokens(in text: String) -> [SourceJSONToken]
	{
		let source = text as NSString
		var tokens: [SourceJSONToken] = []
		expression.enumerateMatches(
			in: text,
			range: NSRange(
				location: 0,
				length: source.length
			)
		)
		{
			match, _, _ in
			guard let range = match?.range
			else
			{
				return
			}
			let first = source.character(at: range.location)
			let style: Style
			if first == 34, hasPrefix(
				"\"",
				at: range.location,
				end: NSMaxRange(range),
				in: source
			)
			{
				let end = NSMaxRange(range)
				let next = source.rangeOfCharacter(
					from: nonWhitespace,
					range: NSRange(
						location: end,
						length: source.length - end
					)
				)
				style = next.location != NSNotFound
					&& hasPrefix(
						":",
						at: next.location,
						end: source.length,
						in: source
					)
					? .key : .string
			}
			else
			{
				style = first == 116 || first == 102 || first == 110 ? .literal : .number
			}
			tokens.append(SourceJSONToken(
				range: range,
				style: style
			))
		}
		return tokens
	}

	private static func hasPrefix(
		_ prefix: String,
		at offset: Int,
		end: Int,
		in source: NSString
	) -> Bool
	{
		// Preserve String's composed-character prefix semantics with only the first scalar's
		// lookahead: a quote or colon followed by a combining mark is not a matching prefix.
		let length = min(
			3,
			end - offset
		)
		return source.substring(with: NSRange(
			location: offset,
			length: length
		)).hasPrefix(prefix)
	}
}
