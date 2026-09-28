import Foundation

enum ReviewAnalyzer
{
	static func review(
		threadID: String,
		turn: CodexTurn,
		earlierTurns: [CodexTurn] = [],
		laterTurns: [CodexTurn],
		hasEarlierHistory: Bool = false,
		hasLaterLiveChanges: Bool = false
	) -> ReviewTurn
	{
		let earlierChanges = earlierTurns.flatMap
		{
			completedChanges(in: $0)
		}
		let changes = completedChanges(in: turn)
		var pathsInOrder: [String] = []
		var changesByPath: [String: [FileChange]] = [:]
		for change in changes
		{
			let path = change.movePath ?? change.path
			if changesByPath[path] == nil
			{
				pathsInOrder.append(path)
			}
			changesByPath[path, default: []].append(change)
		}
		let files = pathsInOrder.compactMap
		{
			path in
			changesByPath[path].map(makeFile)
		}
		let allLaterChanges = laterTurns.flatMap
		{
			completedChanges(in: $0)
		}
		let finalState = codeStateID(
			threadID: threadID,
			hasEarlierHistory: hasEarlierHistory,
			changes: earlierChanges + changes
		)

		var changesBeforeCommand = earlierChanges
		var validations: [ReviewValidation] = []
		for (index, item) in turn.items.enumerated()
		{
			if item.type == "fileChange", item.status == "completed"
			{
				changesBeforeCommand += item.changes
			}
			guard item.type == "commandExecution", let command = item.command
			else
			{
				continue
			}
			let hasLaterChangesInTurn = turn.items.dropFirst(index + 1).contains
			{
				$0.type == "fileChange" && $0.status == "completed" && !$0.changes.isEmpty
			}
			let validationIsOutdated =
				hasLaterChangesInTurn || !allLaterChanges.isEmpty || hasLaterLiveChanges
			let outcome = commandOutcome(for: item)
			let stateID = codeStateID(
				threadID: threadID,
				hasEarlierHistory: hasEarlierHistory,
				changes: changesBeforeCommand
			)
			validations.append(
				ReviewValidation(
					threadID: threadID,
					turnID: turn.id,
					itemID: item.id,
					command: command,
					cwd: item.cwd,
					output: item.output,
					exitCode: item.exitCode,
					outcome: outcome,
					currency: validationIsOutdated ? .outdated : .uncertain,
					codeStateID: stateID,
					hasUnknownEarlierHistory: hasEarlierHistory
				)
			)
		}

		if !files.isEmpty
		{
			let laterStateChanged = !allLaterChanges.isEmpty || hasLaterLiveChanges
			for laterTurn in laterTurns
			{
				var encounteredEdit = false
				for item in laterTurn.items
				{
					if item.type == "fileChange", item.status == "completed", !item.changes.isEmpty
					{
						encounteredEdit = true
						break
					}
					guard item.type == "commandExecution",
							let command = item.command
					else
					{
						continue
					}
					let outcome = commandOutcome(for: item)
					validations.append(
						ReviewValidation(
							threadID: threadID,
							turnID: laterTurn.id,
							itemID: item.id,
							command: command,
							cwd: item.cwd,
							output: item.output,
							exitCode: item.exitCode,
							outcome: outcome,
							currency: laterStateChanged ? .outdated : .uncertain,
							codeStateID: finalState,
							hasUnknownEarlierHistory: hasEarlierHistory
						)
					)
				}
				if encounteredEdit
				{
					break
				}
			}
		}

		return ReviewTurn(
			threadID: threadID,
			turnID: turn.id,
			files: files,
			validations: validations,
			codeStateID: finalState,
			hasUnknownEarlierHistory: hasEarlierHistory
		)
	}

	private static func makeFile(_ changes: [FileChange]) -> ReviewFile
	{
		guard let change = changes.last
		else
		{
			preconditionFailure("A reviewed file needs a change")
		}
		let combinedDiff = changes.map(\.diff).joined(separator: "\n")
		let lines = combinedDiff.components(separatedBy: "\n")
		let reportedMovePath = changes.compactMap(\.movePath).last
		let rename = GitDiffParser.renamePaths(in: combinedDiff)
		let previousPath = rename.old ?? changes.first(where:
			{
				$0.movePath != nil
			})?.path
		let renamedPath = rename.new
		let isBinary = lines.contains
		{
			$0.hasPrefix("Binary files ") || $0 == "GIT binary patch" || $0.hasPrefix("literal ")
		}
		let kind: ReviewFileKind
		let normalized = change.kind.lowercased()
		if isBinary
		{
			kind = .binary
		}
		else if previousPath != nil || reportedMovePath != nil || normalized == "move"
			|| normalized == "rename"
		{
			kind = .renamed
		}
		else if ["delete", "deleted", "remove"].contains(normalized)
		{
			kind = .deleted
		}
		else if ["add", "added", "create"].contains(normalized)
		{
			kind = .added
		}
		else if ["update", "modify", "modified"].contains(normalized)
		{
			kind = .modified
		}
		else
		{
			kind = .unsupported
		}

		let hunks = GitDiffParser.hunks(in: combinedDiff).enumerated().map
		{
			index, hunk in
			let digest = fingerprint([hunk.text])
			return ReviewHunk(
				id: "\(index + 1)-\(digest)",
				header: hunk.header,
				text: hunk.text,
				fingerprint: digest
			)
		}

		let explanation: String?
		switch kind
		{
		case .binary: explanation = "Binary change; text sections are unavailable."
		case .unsupported: explanation = "Unsupported change type: \(change.kind)."
		case .renamed where hunks.isEmpty: explanation = "Renamed without a text section."
		case .deleted where hunks.isEmpty: explanation = "Deleted file; no text section was "
			+ "reported."
		case .added,
				.modified where hunks.isEmpty:
			explanation = "No text sections were reported for this file."
		default: explanation = nil
		}
		return ReviewFile(
			path: renamedPath ?? reportedMovePath ?? change.path,
			previousPath: previousPath,
			reportedMovePath: reportedMovePath,
			kind: kind,
			hunks: hunks,
			diff: combinedDiff,
			fingerprint: fingerprint(changes.map(changeIdentity)),
			explanation: explanation
		)
	}

	private static func completedChanges(in turn: CodexTurn) -> [FileChange]
	{
		turn.items.filter
		{
			$0.type == "fileChange" && $0.status == "completed"
		}
		.flatMap(\.changes)
	}

	private static func commandOutcome(for item: CodexItem) -> ReviewValidationOutcome
	{
		if let exitCode = item.exitCode
		{
			return exitCode == 0 ? .succeeded : .failed
		}
		if item.status == "failed"
		{
			return .failed
		}
		if item.status == "completed" || !(item.output ?? "").isEmpty
		{
			return .unknown
		}
		return .unobserved
	}

	private static func codeStateID(
		threadID: String,
		hasEarlierHistory: Bool,
		changes: [FileChange]
	)
		-> String
	{
		fingerprint(
			[threadID, hasEarlierHistory ? "earlier-history-not-loaded" : "loaded-history"]
				+ changes.map(changeIdentity)
		)
	}

	private static func changeIdentity(_ change: FileChange) -> String
	{
		"\(change.path)\u{0}\(change.movePath ?? "")\u{0}\(change.kind)\u{0}\(change.diff)"
	}

	/// Deterministic FNV-1a over UTF-8; local identity only, not a security digest.
	private static func fingerprint(_ parts: [String]) -> String
	{
		var value: UInt64 = 14_695_981_039_346_656_037
		for part in parts
		{
			for byte in part.utf8
			{
				value = (value ^ UInt64(byte)) &* 1_099_511_628_211
			}
			value = (value ^ 0xff) &* 1_099_511_628_211
		}
		return String(
			value,
			radix: 16
		)
	}
}
