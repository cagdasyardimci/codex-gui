import Foundation

/// Historical turn edits remain available after commits and independent working-tree edits.
enum GitReportedTurnComparison
{
	static func compare(
		_ changes: [FileChange],
		request: GitComparisonRequest
	) -> GitComparisonResult
	{
		let mergedChanges = ConversationNetFileChanges.merge(changes)
		let filePatches = mergedChanges.map
		{
			patchText(
				for: $0,
				repositoryRoot: request.repositoryRoot
			)
		}
		let text = filePatches.joined(separator: "\n")
		let patch = Data((text.isEmpty ? "" : text + "\n").utf8)
		guard patch.count <= 8 * 1024 * 1024
		else
		{
			return .unavailable(.oversized)
		}
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: UUID().uuidString,
			resolvedBase: "Before last editing turn",
			resolvedTarget: "Recorded turn edits",
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch)
		))
	}

	private static func patchText(
		for change: FileChange,
		repositoryRoot: String
	) -> String
	{
		let oldPath = relativePath(
			change.path,
			root: repositoryRoot
		)
		let newPath = relativePath(
			change.movePath ?? change.path,
			root: repositoryRoot
		)
		var lines = ["diff --git \(quoted("a/" + oldPath)) \(quoted("b/" + newPath))"]
		if change.kind == "add"
		{
			lines.append("new file mode 100644")
		}
		if change.kind == "delete"
		{
			lines.append("deleted file mode 100644")
		}
		if oldPath != newPath
		{
			lines.append("rename from " + quoted(oldPath))
			lines.append("rename to " + quoted(newPath))
		}
		lines.append("--- " + (change.kind == "add" ? "/dev/null" : quoted("a/" + oldPath)))
		lines.append("+++ " + (change.kind == "delete" ? "/dev/null" : quoted("b/" + newPath)))
		lines.append(change.diff)
		return lines.joined(separator: "\n")
	}

	private static func relativePath(
		_ path: String,
		root: String
	) -> String
	{
		let prefix = root.hasSuffix("/") ? root : root + "/"
		return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
	}

	private static func quoted(_ path: String) -> String
	{
		"\"" + path.replacingOccurrences(
			of: "\\",
			with: "\\\\"
		)
		.replacingOccurrences(
			of: "\"",
			with: "\\\""
		)
		.replacingOccurrences(
			of: "\t",
			with: "\\t"
		)
		.replacingOccurrences(
			of: "\n",
			with: "\\n"
		)
		.replacingOccurrences(
			of: "\r",
			with: "\\r"
		) + "\""
	}
}
