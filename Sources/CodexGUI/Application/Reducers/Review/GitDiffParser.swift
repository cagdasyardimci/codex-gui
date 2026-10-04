import Foundation

/// Interprets reported Git diffs independently of AppKit and editor launching.
enum GitDiffParser
{
	static func decodedPath(_ value: String) -> String?
	{
		GitPatchSyntax.decodedPath(value)
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
		hunks(in: diff.components(separatedBy: "\n")).hunks
	}

	/// Reuses LF-separated patch lines and counts changes while visiting each hunk body.
	static func hunks(
		in lines: [String]
	) -> (hunks: [(header: String, text: String)], additions: Int, deletions: Int)
	{
		var hunks: [(header: String, text: String)] = []
		var currentHeader: String?
		var hunkLines: [String] = []
		var additions = 0
		var deletions = 0

		func finishCurrentHunk()
		{
			guard let header = currentHeader
			else
			{
				return
			}
			hunks.append((header, hunkLines.joined(separator: "\n")))
			currentHeader = nil
			hunkLines = []
		}

		for line in lines
		{
			if line.hasPrefix("diff --git ")
			{
				finishCurrentHunk()
			}
			if line.hasPrefix("@@ ")
			{
				finishCurrentHunk()
				currentHeader = line
			}
			if currentHeader != nil
			{
				hunkLines.append(line)
				if line.hasPrefix("+")
				{
					additions += 1
				}
				else if line.hasPrefix("-")
				{
					deletions += 1
				}
			}
		}

		finishCurrentHunk()
		return (hunks, additions, deletions)
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

		if let pair = GitPatchSyntax.unquotedHeaderCandidates(header).first(where:
			{
				!$0.old.isEmpty && !$0.new.trimmingCharacters(in: .whitespaces).isEmpty
			})
		{
			old.append(pair.old)
			new.append(pair.new.trimmingCharacters(in: .whitespaces))
		}
		else if let pair = GitPatchSyntax.headerFields(header)
		{
			old.append(removingSidePrefix(
				pair.old,
				side: "a"
			))
			new.append(removingSidePrefix(
				pair.new,
				side: "b"
			))
		}
		return (old, new)
	}

	/// Reported diffs keep literal unquoted marker suffixes supplied by the backend.
	private static func appendHeaderPath(
		_ value: String,
		side: String,
		to paths: inout [String]
	)
	{
		guard value != "/dev/null", let path = GitPatchSyntax.decodedPath(value)
		else
		{
			return
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
