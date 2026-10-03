import Foundation

/// Rewrites complete metadata fields, never hunk lines or nested path substrings.
enum GitTurnBaselinePatchNormalizer
{
	static func normalize(_ bytes: Data) -> Data
	{
		let lines = bytes.split(
			separator: 10,
			omittingEmptySubsequences: false
		).map
		{
			Data($0)
		}
		var sections: [[Data]] = []
		for line in lines
		{
			if line.starts(with: Data("diff --git ".utf8))
			{
				sections.append([line])
			}
			else if !sections.isEmpty
			{
				sections[sections.count - 1].append(line)
			}
		}
		var output = Data()
		for (sectionIndex, section) in sections.enumerated()
		{
			let paths = sectionPaths(section)
			var inHunk = false
			for (lineIndex, line) in section.enumerated()
			{
				if line.starts(with: Data("@@ ".utf8))
				{
					inHunk = true
				}

				var value = line
				if !inHunk, let text = String(
					data: line,
					encoding: .utf8
				)
				{
					value = normalizedMetadataLine(
						text,
						paths: paths,
						original: line
					)
				}
				output.append(value)
				if lineIndex < section.count - 1 || sectionIndex < sections.count - 1
				{
					output.append(10)
				}
			}
		}
		return output
	}

	private static func normalizedMetadataLine(
		_ text: String,
		paths: (old: String?, new: String?),
		original: Data
	) -> Data
	{
		var value = original
		if text.hasPrefix("diff --git "), let old = paths.old, let new = paths.new
		{
			value = Data(("diff --git " + quoted("a/" + old) + " " + quoted("b/" + new))
				.utf8)
		}
		else if text.hasPrefix("--- ") || text.hasPrefix("+++ ")
		{
			let prefix = String(text.prefix(4))
			let field = String(text.dropFirst(4))
			if field != "/dev/null", let path = GitPatchSyntax.decodedField(field)
			{
				let side = text.hasPrefix("--- ") ? "a/" : "b/"
				value = Data((prefix + quoted(side + removeScratch(path))).utf8)
			}
		}
		else if text.hasPrefix("Binary files "), let old = paths.old,
				let new = paths.new
		{
			let oldField = text.hasPrefix("Binary files /dev/null and ")
				? "/dev/null" : quoted("a/" + old)
			let newField = text.hasSuffix(" and /dev/null differ")
				? "/dev/null" : quoted("b/" + new)
			value = Data(("Binary files " + oldField + " and " + newField + " differ")
				.utf8)
		}
		else
		{
			for prefix in ["rename from ", "rename to ", "copy from ", "copy to "]
				where text.hasPrefix(prefix)
			{
				if let path = GitPatchSyntax
					.decodedField(String(text.dropFirst(prefix.count)))
				{
					value = Data((prefix + quoted(removeTreePrefix(path))).utf8)
				}
			}
		}
		return value
	}

	private static func sectionPaths(_ lines: [Data]) -> (old: String?, new: String?)
	{
		var old: String?
		var new: String?
		for line in lines
		{
			guard let text = String(
				data: line,
				encoding: .utf8
			)
			else
			{
				continue
			}
			if text.hasPrefix("@@ ")
			{
				break
			}
			for (prefix, isOld) in [("--- ", true),
									("+++ ", false),
									("rename from ", true),
									("rename to ", false),
									("copy from ", true),
									("copy to ", false)]
				where text.hasPrefix(prefix)
			{
				let field = String(text.dropFirst(prefix.count))
				guard field != "/dev/null", let path = GitPatchSyntax.decodedField(field)
				else
				{
					continue
				}
				let normalized = prefix.count == 4 ? removeScratch(path) : removeTreePrefix(path)
				if isOld
				{
					old = normalized
				}
				else
				{
					new = normalized
				}
			}
		}
		if old != nil || new != nil
		{
			return (old ?? new, new ?? old)
		}
		guard let header = lines.first.flatMap(
			{
				String(
					data: $0,
					encoding: .utf8
				)
			}
		)
		else
		{
			return (nil, nil)
		}
		if header.hasPrefix("diff --git \""), let fields = GitPatchSyntax.headerFields(header)
		{
			return (
				removeScratch(fields.old),
				removeScratch(fields.new)
			)
		}
		// Binary and mode-only changes without other metadata use a same-path header.
		for pair in GitPatchSyntax.unquotedHeaderCandidates(header)
		{
			let oldPath = removeScratch("a/" + pair.old)
			let newPath = removeScratch("b/" + pair.new)
			if oldPath == newPath
			{
				return (oldPath, newPath)
			}
		}
		return (nil, nil)
	}

	private static func removeScratch(_ field: String) -> String
	{
		for prefix in ["a/before/", "a/after/", "b/before/", "b/after/"]
			where field.hasPrefix(prefix)
		{
			return String(field.dropFirst(prefix.count))
		}
		return field
	}

	private static func removeTreePrefix(_ field: String) -> String
	{
		for prefix in ["before/", "after/"] where field.hasPrefix(prefix)
		{
			return String(field.dropFirst(prefix.count))
		}
		return field
	}

	private static func quoted(_ path: String) -> String
	{
		var result = ""
		var needsQuotes = false
		for byte in path.utf8
		{
			switch byte
			{
			case 9:
				result += "\\t"
				needsQuotes = true
			case 10:
				result += "\\n"
				needsQuotes = true
			case 13:
				result += "\\r"
				needsQuotes = true
			case 34:
				result += "\\\""
				needsQuotes = true
			case 92:
				result += "\\\\"
				needsQuotes = true
			case 32 ... 126: result.append(Character(UnicodeScalar(byte)))
			default:
				result += String(
					format: "\\%03o",
					byte
				)
				needsQuotes = true
			}
		}
		return needsQuotes ? "\"" + result + "\"" : result
	}
}
