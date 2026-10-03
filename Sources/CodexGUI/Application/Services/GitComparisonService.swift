import Foundation

protocol GitComparisonService: Sendable
{
	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
}

enum GitComparisonPatchParser
{
	static func hasUnsupportedSections(in data: Data) -> Bool
	{
		let patch = String(
			decoding: data,
			as: UTF8.self
		)
		return patch.components(separatedBy: "\n").contains
		{
			$0.hasPrefix("diff --cc ") || $0.hasPrefix("diff --combined ")
				|| $0.hasPrefix("* Unmerged path ")
		}
	}

	static func files(in data: Data) -> [GitComparisonFile]
	{
		let text = String(
			decoding: data,
			as: UTF8.self
		)
		var sections: [[String]] = []
		for line in text.components(separatedBy: "\n")
		{
			if line.hasPrefix("diff --cc ") || line.hasPrefix("diff --combined ")
				|| line.hasPrefix("* Unmerged path ")
			{
				sections.append([])
				continue
			}
			if line.hasPrefix("diff --git ")
			{
				sections.append([line])
			}
			else if !sections.isEmpty && !sections[sections.count - 1].isEmpty
			{
				sections[sections.count - 1].append(line)
			}
		}
		return coalesced(sections.filter
		{
			!$0.isEmpty
		}.map(file))
	}

	/// Git can emit deletion and addition sections for a symlink/regular-file type change.
	/// Coalescing preserves the payload while keeping path-based navigation identities unique.
	private static func coalesced(_ files: [GitComparisonFile]) -> [GitComparisonFile]
	{
		var positions: [String: Int] = [:]
		var result: [GitComparisonFile] = []
		for file in files
		{
			if let index = positions[file.path]
			{
				let previous = result[index]
				let rename = [previous, file].first
				{
					$0.kind == .renamed
				}
				result[index] = GitComparisonFile(
					oldPath: rename?.oldPath ?? previous.oldPath ?? file.oldPath,
					newPath: file.newPath ?? previous.newPath,
					kind: rename == nil ? .modified : .renamed,
					additions: previous.additions + file.additions,
					deletions: previous.deletions + file.deletions,
					isBinary: previous.isBinary || file.isBinary,
					patch: previous.patch + "\n" + file.patch,
					hunks: previous.hunks + file.hunks
				)
			}
			else
			{
				positions[file.path] = result.count
				result.append(file)
			}
		}
		return result
	}

	private static func file(_ lines: [String]) -> GitComparisonFile
	{
		let patch = lines.joined(separator: "\n")
		let metadata = lines.prefix
		{
			!$0.hasPrefix("@@ ")
		}
		var oldPath: String?
		var newPath: String?
		var kind: GitComparisonChangeKind = .modified
		for line in metadata
		{
			if line.hasPrefix("--- ")
			{
				oldPath = GitPatchSyntax.markerPath(
					String(line.dropFirst(4)),
					side: "a/"
				)
			}
			if line.hasPrefix("+++ ")
			{
				newPath = GitPatchSyntax.markerPath(
					String(line.dropFirst(4)),
					side: "b/"
				)
			}
			if line.hasPrefix("rename from ")
			{
				oldPath = GitPatchSyntax.decodedPath(String(line.dropFirst(12)))
				kind = .renamed
			}
			if line.hasPrefix("rename to ")
			{
				newPath = GitPatchSyntax.decodedPath(String(line.dropFirst(10)))
			}
			if line.hasPrefix("new file mode ")
			{
				kind = .added
			}
			if line.hasPrefix("deleted file mode ")
			{
				kind = .deleted
			}
		}
		// Mode-only and binary sections have no ---/+++ markers; same-path headers are enough.
		if oldPath == nil && newPath == nil,
			let fallback = samePathHeader(lines.first ?? "")
			?? GitDiffParser.filePaths(in: patch).first
		{
			oldPath = kind == .added ? nil : fallback
			newPath = kind == .deleted ? nil : fallback
		}
		let hunks = GitDiffParser.hunks(in: patch).map
		{
			hunk in
			GitComparisonHunk(
				header: hunk.header,
				text: hunk.text,
				oldStart: start(
					in: hunk.header,
					marker: "-"
				),
				newStart: start(
					in: hunk.header,
					marker: "+"
				)
			)
		}
		let hunkLines = hunks.flatMap
		{
			$0.text.components(separatedBy: "\n").dropFirst()
		}
		return GitComparisonFile(
			oldPath: oldPath,
			newPath: newPath,
			kind: kind,
			additions: hunkLines.filter
			{
				$0.hasPrefix("+")
			}.count,
			deletions: hunkLines.filter
			{
				$0.hasPrefix("-")
			}.count,
			isBinary: metadata
				.contains
				{
					$0.hasPrefix("Binary files ") || $0 == "GIT binary patch"
				},
			patch: patch,
			hunks: hunks
		)
	}

	/// Unquoted names may contain " b/"; only accept a split with identical paths.
	private static func samePathHeader(_ header: String) -> String?
	{
		GitPatchSyntax.unquotedHeaderCandidates(header).first
		{
			$0.old == $0.new
		}?.old
	}

	private static func start(
		in header: String,
		marker: String
	) -> Int
	{
		guard let range = header.range(
			of: marker + "[0-9]+",
			options: .regularExpression
		)
		else
		{
			return 0
		}
		return Int(header[range].dropFirst()) ?? 0
	}
}
