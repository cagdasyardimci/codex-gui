import Foundation

/// Historical turn edits remain available after commits and independent working-tree edits.
enum GitReportedTurnComparison
{
	static let coverageMessage = "Reported edits only; shell edits and unreported subagent edits "
		+ "are excluded."

	static let fallbackMessage = "Reported edit counts; repeated edits may be counted "
		+ "more than once. These are not net changes."

	static func compare(_ request: GitComparisonRequest) -> GitComparisonResult
	{
		guard request.owner.selectedThreadID != nil, request.lastTurnID != nil,
				let changes = request.reportedChanges
		else
		{
			return .unavailable(.lastTurnUnavailable)
		}
		return compare(
			changes,
			request: request
		)
	}

	static func compare(
		_ changes: [FileChange],
		request: GitComparisonRequest
	) -> GitComparisonResult
	{
		let composition = ConversationNetFileChanges.compose(ReportedRepositoryFileChanges.filter(
			changes,
			repositoryRoot: request.repositoryRoot
		))
		let filePatches = composition.changes.map
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
			resolvedBase: composition.isExact ? "Before last editing turn" : "Reported edits",
			resolvedTarget: composition.isExact ? "Recorded turn edits" : "Reported edit counts",
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch),
			usesReportedEditFallback: !composition.isExact
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
