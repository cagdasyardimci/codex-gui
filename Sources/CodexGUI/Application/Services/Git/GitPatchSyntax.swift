import Foundation

/// Git's quoted path fields and the path markers shared by patch consumers.
enum GitPatchSyntax
{
	typealias HeaderCandidate = (old: String, new: String)

	static func decodedPath(_ value: String) -> String?
	{
		guard value.first == "\""
		else
		{
			return value
		}
		var cursor = value.startIndex
		return parseToken(
			value,
			at: &cursor
		)
	}

	/// An unquoted trailing tab separates a path from optional marker metadata.
	static func decodedField(_ value: String) -> String?
	{
		let field = value.first != "\"" && value.hasSuffix("\t")
			? String(value.dropLast()) : value
		return decodedPath(field)
	}

	static func markerPath(
		_ value: String,
		side: String
	) -> String?
	{
		let token = value.first != "\"" && value.hasSuffix("\t")
			? String(value.dropLast()) : value
		guard token != "/dev/null", let decoded = decodedPath(token)
		else
		{
			return nil
		}
		return decoded.hasPrefix(side) ? String(decoded.dropFirst(side.count)) : decoded
	}

	/// Extract the two Git path tokens; consumers decide how to treat ambiguous synthetic headers.
	static func headerFields(_ header: String) -> (old: String, new: String)?
	{
		guard header.hasPrefix("diff --git ")
		else
		{
			return nil
		}
		let fields = String(header.dropFirst("diff --git ".count))
		var cursor = fields.startIndex
		guard let old = parseToken(
			fields,
			at: &cursor
		),
			let new = parseToken(
				fields,
				at: &cursor
			)
		else
		{
			return nil
		}
		return (old, new)
	}

	/// Yields possible splits lazily; callers apply their own acceptance policy.
	static func unquotedHeaderCandidates(_ header: String) -> AnySequence<HeaderCandidate>
	{
		guard header.hasPrefix("diff --git a/")
		else
		{
			return AnySequence([])
		}
		let fields = String(header.dropFirst("diff --git a/".count))
		return AnySequence
		{
			var cursor = fields.startIndex
			return AnyIterator<HeaderCandidate>
			{
				guard cursor < fields.endIndex,
						let separator = fields.range(
						of: " b/",
						range: cursor ..< fields.endIndex
						)
				else
				{
					return nil
				}
				cursor = separator.upperBound
				return (
					String(fields[..<separator.lowerBound]),
					String(fields[separator.upperBound...])
				)
			}
		}
	}

	private static func parseToken(
		_ text: String,
		at cursor: inout String.Index
	) -> String?
	{
		while cursor < text.endIndex && text[cursor].isWhitespace
		{
			cursor = text.index(after: cursor)
		}
		guard cursor < text.endIndex
		else
		{
			return nil
		}
		if text[cursor] != "\""
		{
			let start = cursor
			while cursor < text.endIndex && !text[cursor].isWhitespace
			{
				cursor = text.index(after: cursor)
			}
			return String(text[start ..< cursor])
		}
		return parseQuotedToken(
			text,
			at: &cursor
		)
	}

	// Git quotes paths as UTF-8 bytes, including up to three octal digits per escaped byte.
	private static func parseQuotedToken(
		_ text: String,
		at cursor: inout String.Index
	) -> String?
	{
		cursor = text.index(after: cursor)
		var decodedBytes: [UInt8] = []
		while cursor < text.endIndex
		{
			let character = text[cursor]
			cursor = text.index(after: cursor)
			if character == "\""
			{
				return String(
					decoding: decodedBytes,
					as: UTF8.self
				)
			}
			if character != "\\"
			{
				decodedBytes.append(contentsOf: String(character).utf8)
				continue
			}
			guard cursor < text.endIndex
			else
			{
				return nil
			}
			let escaped = text[cursor]
			cursor = text.index(after: cursor)
			switch escaped
			{
			case "t": decodedBytes.append(9)
			case "n": decodedBytes.append(10)
			case "r": decodedBytes.append(13)
			case "\\", "\"": decodedBytes.append(contentsOf: String(escaped).utf8)
			case "0" ... "7":
				var digits = String(escaped)
				for _ in 0 ..< 2
					where cursor < text.endIndex && ("0" ... "7").contains(text[cursor])
				{
					digits.append(text[cursor])
					cursor = text.index(after: cursor)
				}
				guard let byte = UInt8(
					digits,
					radix: 8
				)
				else
				{
					return nil
				}
				decodedBytes.append(byte)
			default: decodedBytes.append(contentsOf: String(escaped).utf8)
			}
		}
		return nil
	}
}
