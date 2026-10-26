import Foundation

/// A deliberately bounded YAML subset. Unsupported syntax stays in the Markdown body verbatim.
struct MarkdownFileMetadata: Sendable, Equatable
{
	struct Entry: Sendable, Equatable
	{
		let key: String
		let values: [String]
		let isSequence: Bool
	}

	let entries: [Entry]
	let body: String

	static func parse(_ source: String) -> MarkdownFileMetadata?
	{
		let text = source as NSString
		var offset = 0
		var lines: [String] = []
		var closed = false
		while offset < text.length, offset < 65_536
		{
			let range = text.lineRange(for: NSRange(
				location: offset,
				length: 0
			))
			guard NSMaxRange(range) <= 65_536
			else
			{
				return nil
			}
			var line = text.substring(with: range).trimmingCharacters(in: .newlines)
			guard !line.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
			else
			{
				return nil
			}
			if offset == 0
			{
				if line.hasPrefix("\u{feff}")
				{
					line.removeFirst()
				}
				guard line == "---"
				else
				{
					return nil
				}
			}
			else if line == "---" || line == "..."
			{
				closed = true
				offset = NSMaxRange(range)
				break
			}
			else
			{
				lines.append(line)
			}
			offset = NSMaxRange(range)
		}
		guard closed, let entries = parseEntries(lines), !entries.isEmpty
		else
		{
			return nil
		}
		return MarkdownFileMetadata(
			entries: entries,
			body: text.substring(from: offset)
		)
	}

	private static func parseEntries(_ lines: [String]) -> [Entry]?
	{
		var entries: [Entry] = []
		var keys: Set<String> = []
		var index = 0
		while index < lines.count
		{
			let line = lines[index]
			index += 1
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.isEmpty || trimmed.hasPrefix("#")
			{
				continue
			}
			guard !line.hasPrefix(" "), !line.contains("\t"),
					let colon = line.firstIndex(of: ":")
			else
			{
				return nil
			}
			let key = String(line[..<colon])
			guard key.range(
				of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#,
				options: .regularExpression
			) != nil, keys.insert(key).inserted,
				entries.count < 128
			else
			{
				return nil
			}
			let remainder = line[line.index(after: colon)...]
			guard remainder.isEmpty || remainder.first == " "
			else
			{
				return nil
			}
			let value = remainder.trimmingCharacters(in: .whitespaces)
			if value.isEmpty || value.hasPrefix("#")
			{
				var values: [String] = []
				var sequenceIndent: Int?
				while index < lines.count
				{
					let candidate = lines[index]
					let item = candidate.trimmingCharacters(in: .whitespaces)
					if item.isEmpty || item.hasPrefix("#")
					{
						index += 1
						continue
					}
					guard candidate.hasPrefix(" ")
					else
					{
						break
					}
					let indent = candidate.prefix(while:
						{
							$0 == " "
						}).count
					if let sequenceIndent, sequenceIndent != indent
					{
						return nil
					}
					sequenceIndent = indent
					guard !candidate.contains("\t"), item.hasPrefix("- "), values.count < 256,
							let scalar = scalar(String(item.dropFirst(2)))
					else
					{
						return nil
					}
					values.append(scalar)
					index += 1
				}
				entries.append(Entry(
					key: key,
					values: values.isEmpty ? [""] : values,
					isSequence: !values.isEmpty
				))
			}
			else if value.hasPrefix("[")
			{
				guard let values = sequence(value)
				else
				{
					return nil
				}
				entries.append(Entry(
					key: key,
					values: values,
					isSequence: true
				))
			}
			else
			{
				guard let scalar = scalar(value)
				else
				{
					return nil
				}
				entries.append(Entry(
					key: key,
					values: [scalar],
					isSequence: false
				))
			}
		}
		return entries
	}

	private static func scalar(_ source: String) -> String?
	{
		let value = source.trimmingCharacters(in: .whitespaces)
		guard !value.isEmpty
		else
		{
			return nil
		}
		if value.hasPrefix("\"")
		{
			guard let end = quotedEnd(
				value,
				quote: "\""
			),
				validSuffix(String(value[value.index(after: end)...]))
			else
			{
				return nil
			}
			let quoted = String(value[...end])
			return (try? JSONSerialization.jsonObject(
				with: Data(quoted.utf8),
				options: .fragmentsAllowed
			)) as? String
		}
		if value.hasPrefix("'")
		{
			guard let end = quotedEnd(
				value,
				quote: "'"
			),
				validSuffix(String(value[value.index(after: end)...]))
			else
			{
				return nil
			}
			return String(value[value.index(after: value.startIndex) ..< end])
				.replacingOccurrences(
					of: "''",
					with: "'"
				)
		}
		guard let first = value.first, !"!&*{}[],#|>@`%\"'".contains(first),
				value != "-", value != "?", value != ":",
				!value.hasPrefix("- "), !value.hasPrefix("? "),
				value.range(
				of: #":(?:\s|$)"#,
				options: .regularExpression
				) == nil,
				!value.contains("\t")
		else
		{
			return nil
		}
		if let comment = value.range(of: " #")
		{
			return String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
		}
		return value
	}

	private static func quotedEnd(
		_ value: String,
		quote: Character
	) -> String.Index?
	{
		var index = value.index(after: value.startIndex)
		while index < value.endIndex
		{
			let character = value[index]
			let next = value.index(after: index)
			if character == quote
			{
				if quote == "'", next < value.endIndex, value[next] == "'"
				{
					index = value.index(after: next)
					continue
				}
				return index
			}
			if quote == "\"", character == "\\", next < value.endIndex
			{
				index = value.index(after: next)
			}
			else
			{
				index = next
			}
		}
		return nil
	}

	private static func validSuffix(_ source: String) -> Bool
	{
		source.isEmpty || (source.hasPrefix(" ") &&
			source.trimmingCharacters(in: .whitespaces).hasPrefix("#")) ||
			source.trimmingCharacters(in: .whitespaces).isEmpty
	}

	private static func sequence(_ source: String) -> [String]?
	{
		var values: [String] = []
		var remaining = String(source.dropFirst()).trimmingCharacters(in: .whitespaces)
		while !remaining.hasPrefix("]")
		{
			guard !remaining.isEmpty, values.count < 256
			else
			{
				return nil
			}
			let end: String.Index
			if let quote = remaining.first, quote == "'" || quote == "\""
			{
				guard let quoted = quotedEnd(
					remaining,
					quote: quote
				)
				else
				{
					return nil
				}
				end = remaining.index(after: quoted)
			}
			else
			{
				guard let delimiter = remaining.firstIndex(where:
					{
						$0 == "," || $0 == "]"
					})
				else
				{
					return nil
				}
				end = delimiter
				guard !remaining[..<end].contains(where:
					{
						"[]{}#".contains($0)
					})
				else
				{
					return nil
				}
			}
			guard let item = scalar(String(remaining[..<end])), !item.isEmpty
			else
			{
				return nil
			}
			values.append(item)
			remaining = String(remaining[end...]).trimmingCharacters(in: .whitespaces)
			if remaining.hasPrefix(",")
			{
				remaining = String(remaining.dropFirst()).trimmingCharacters(in: .whitespaces)
			}
			else if !remaining.hasPrefix("]")
			{
				return nil
			}
		}
		guard validSuffix(String(remaining.dropFirst()))
		else
		{
			return nil
		}
		return values
	}
}
