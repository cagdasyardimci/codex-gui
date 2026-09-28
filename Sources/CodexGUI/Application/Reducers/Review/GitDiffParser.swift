import Foundation

/// Interprets reported Git diffs independently of AppKit and editor launching.
enum GitDiffParser
{
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

	/// Destination paths in report order; deletions retain their original path.
	static func filePaths(in aggregateDiff: String) -> [String]
	{
		var reportedPaths: Set<String> = []
		return sections(in: aggregateDiff).compactMap
		{
			section in
			let paths = sectionPaths(section)
			let metadata = section.components(separatedBy: "\n").prefix
			{
				!$0.hasPrefix("@@ ")
			}
			let isDeletion = metadata.contains("+++ /dev/null")
			guard let path = (isDeletion ? paths.old.first : paths.new.first ?? paths.old.first),
					reportedPaths.insert(path).inserted
			else
			{
				return nil
			}
			return path
		}
	}

	static func selectedDiff(
		for path: String,
		in aggregateDiff: String
	) -> String
	{
		let sections = sections(in: aggregateDiff)
		guard !sections.isEmpty
		else
		{
			return aggregateDiff
		}
		let destinationSections = sections.filter
		{
			section in
			section.components(separatedBy: "\n").first == "diff --git a/\(path) b/\(path)"
				|| sectionPaths(section).new.contains(path)
		}
		if !destinationSections.isEmpty
		{
			return destinationSections.joined(separator: "\n")
		}
		return sections.filter
		{
			sectionPaths($0).old.contains(path)
		}.joined(separator: "\n")
	}

	static func renamePaths(in diff: String) -> (old: String?, new: String?)
	{
		var old: String?
		var new: String?
		var inHunk = false
		for line in diff.components(separatedBy: "\n")
		{
			if line.hasPrefix("diff --git ")
			{
				inHunk = false
			}
			if line.hasPrefix("@@ ")
			{
				inHunk = true
			}
			guard !inHunk
			else
			{
				continue
			}
			if line.hasPrefix("rename from "), old == nil
			{
				old = decodedPath(String(line.dropFirst("rename from ".count)))
			}
			else if line.hasPrefix("rename to ")
			{
				new = decodedPath(String(line.dropFirst("rename to ".count)))
			}
		}
		return (old, new)
	}

	/// Preserve section boundaries when successive changes contain separate Git headers.
	static func hunks(in diff: String) -> [(header: String, text: String)]
	{
		var hunks: [(header: String, text: String)] = []
		var header: String?
		var content: [String] = []
		func finishCurrentHunk()
		{
			guard let currentHeader = header
			else
			{
				return
			}
			hunks.append((currentHeader, content.joined(separator: "\n")))
			header = nil
			content = []
		}
		for line in diff.components(separatedBy: "\n")
		{
			if line.hasPrefix("diff --git ")
			{
				finishCurrentHunk()
			}
			if line.hasPrefix("@@ ")
			{
				finishCurrentHunk()
				header = line
			}
			if header != nil
			{
				content.append(line)
			}
		}
		finishCurrentHunk()
		return hunks
	}

	private static func sections(in diff: String) -> [String]
	{
		var sections: [String] = []
		for line in diff.components(separatedBy: "\n")
		{
			if line.hasPrefix("diff --git ")
			{
				sections.append(line)
			}
			else if !sections.isEmpty
			{
				sections[sections.count - 1] += "\n" + line
			}
		}
		return sections
	}

	static func relevantLine(in diff: String) -> Int?
	{
		let lines = diff.components(separatedBy: .newlines)
		guard let hunkIndex = lines.firstIndex(where:
			{
				$0.hasPrefix("@@ ")
			})
		else
		{
			return nil
		}
		let header = lines[hunkIndex]
		guard
			let range = header.range(
				of: #"\+([0-9]+)(?:,[0-9]+)? @@"#,
				options: .regularExpression
			),
			let start = Int(header[range].dropFirst().prefix
			{
				$0.isNumber
			})
		else
		{
			return nil
		}

		var destinationLine = max(
			1,
			start
		)
		var nearestDeletion: Int?
		for line in lines.dropFirst(hunkIndex + 1)
		{
			if line.hasPrefix("@@ ") || line.hasPrefix("diff --git ")
			{
				break
			}
			if line.hasPrefix("\\")
			{
				continue
			}
			if line.hasPrefix("+")
			{
				return destinationLine
			}
			if line.hasPrefix("-")
			{
				nearestDeletion = destinationLine
			}
			else if line.hasPrefix(" ")
			{
				destinationLine += 1
			}
		}
		return nearestDeletion ?? max(
			1,
			start
		)
	}

	private static func sectionPaths(_ section: String) -> (old: [String], new: [String])
	{
		let lines = section.components(separatedBy: .newlines)
		guard let header = lines.first
		else
		{
			return ([], [])
		}
		let headerPaths = String(header.dropFirst("diff --git ".count))

		// Synthetic headers are useful for diffs that contain paths with spaces.
		var old: [String] = []
		var new: [String] = []
		for line in lines.dropFirst().prefix(while:
			{
				!$0.hasPrefix("@@ ")
			})
		{
			if line.hasPrefix("rename from ")
			{
				if let path = decodedPath(String(line.dropFirst("rename from ".count)))
				{
					old.append(path)
				}
			}
			else if line.hasPrefix("rename to ")
			{
				if let path = decodedPath(String(line.dropFirst("rename to ".count)))
				{
					new.append(path)
				}
			}
			else if line.hasPrefix("--- ")
			{
				appendHeaderPath(
					String(line.dropFirst(4)),
					side: "a",
					to: &old
				)
			}
			else if line.hasPrefix("+++ ")
			{
				appendHeaderPath(
					String(line.dropFirst(4)),
					side: "b",
					to: &new
				)
			}
		}

		if let pair = syntheticHeaderPaths(headerPaths)
		{
			old.append(pair.old)
			new.append(pair.new)
		}
		else if let pair = tokenizedHeaderPaths(headerPaths)
		{
			old.append(pair.old)
			new.append(pair.new)
		}
		return (old, new)
	}

	private static func syntheticHeaderPaths(_ header: String) -> (old: String, new: String)?
	{
		guard header.hasPrefix("a/")
		else
		{
			return nil
		}
		let source = header.dropFirst(2)
		let delimiter = " b/"
		guard let split = source.range(of: delimiter)
		else
		{
			return nil
		}
		let old = String(source[..<split.lowerBound])
		let new = String(source[split.upperBound...]).trimmingCharacters(in: .whitespaces)
		guard !old.isEmpty, !new.isEmpty
		else
		{
			return nil
		}
		return (old, new)
	}

	private static func tokenizedHeaderPaths(_ header: String) -> (old: String, new: String)?
	{
		var cursor = header.startIndex
		guard let oldToken = parseToken(
			header,
			at: &cursor
		),
			let newToken = parseToken(
				header,
				at: &cursor
			)
		else
		{
			return nil
		}
		return (removingSidePrefix(
			oldToken,
			side: "a"
		), removingSidePrefix(
			newToken,
			side: "b"
		))
	}

	private static func parseToken(
		_ text: String,
		at cursor: inout String.Index
	) -> String?
	{
		while cursor < text.endIndex && text[cursor]
			.isWhitespace
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
			return parseUnquotedToken(
				text,
				at: &cursor
			)
		}
		return parseQuotedToken(
			text,
			at: &cursor
		)
	}

	private static func parseUnquotedToken(
		_ text: String,
		at cursor: inout String.Index
	) -> String
	{
		let tokenStart = cursor
		while cursor < text.endIndex && !text[cursor].isWhitespace
		{
			cursor = text.index(after: cursor)
		}
		return String(text[tokenStart ..< cursor])
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

	private static func appendHeaderPath(
		_ value: String,
		side: String,
		to paths: inout [String]
	)
	{
		guard value != "/dev/null"
		else
		{
			return
		}
		let path: String
		if value.first == "\""
		{
			var index = value.startIndex
			guard let token = parseToken(
				value,
				at: &index
			)
			else
			{
				return
			}
			path = token
		}
		else
		{
			path = value
		}
		paths.append(removingSidePrefix(
			path,
			side: side
		))
	}

	private static func removingSidePrefix(
		_ value: String,
		side: String
	) -> String
	{
		let prefix = side + "/"
		return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
	}

}
