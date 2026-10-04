import Foundation

enum ReviewAnalyzer
{
	static func reviews(
		threadID: String,
		turns: [CodexTurn],
		hasEarlierHistory: Bool = false,
		liveChangeTurnID: String? = nil,
		parsedChanges: inout [String: ReviewParsedChanges]
	) -> [ReviewTurn]
	{
		let turnIDs = Set(turns.map(\.id))
		for turnID in parsedChanges.keys where !turnIDs.contains(turnID)
		{
			parsedChanges.removeValue(forKey: turnID)
		}

		let parsedTurns = turns.map
		{
			turn in
			let changes = completedChanges(in: turn)
			if let cached = parsedChanges[turn.id], sameChanges(
				cached.changes,
				changes
			)
			{
				return cached
			}
			let parsed = parse(changes)
			parsedChanges[turn.id] = parsed
			return parsed
		}

		var laterChanges = Array(
			repeating: false,
			count: turns.count
		)
		var encounteredEdit = false
		for index in turns.indices.reversed()
		{
			laterChanges[index] = encounteredEdit
			encounteredEdit = encounteredEdit || !parsedTurns[index].changes.isEmpty
		}
		let liveChangeIndex = liveChangeTurnID.map
		{
			id in
			turns.firstIndex(where:
				{
					$0.id == id
				}) ?? turns.count
		}

		var state = historyFingerprint(
			threadID: threadID,
			hasEarlierHistory: hasEarlierHistory
		)
		return turns.indices.map
		{
			index in
			let hasLaterChanges = laterChanges[index] ||
				(liveChangeIndex.map
				{
					$0 > index
				} ?? false)
			return analyze(
				threadID: threadID,
				turn: turns[index],
				parsed: parsedTurns[index],
				state: &state,
				laterTurns: turns[(index + 1)...],
				hasEarlierHistory: hasEarlierHistory,
				hasLaterChanges: hasLaterChanges
			)
		}
	}

	static func review(
		threadID: String,
		turn: CodexTurn,
		earlierTurns: [CodexTurn] = [],
		laterTurns: [CodexTurn],
		hasEarlierHistory: Bool = false,
		hasLaterLiveChanges: Bool = false
	) -> ReviewTurn
	{
		var state = historyFingerprint(
			threadID: threadID,
			hasEarlierHistory: hasEarlierHistory
		)
		for earlierTurn in earlierTurns
		{
			for change in completedChanges(in: earlierTurn)
			{
				state.append(changeIdentity(change))
			}
		}
		return analyze(
			threadID: threadID,
			turn: turn,
			parsed: parse(completedChanges(in: turn)),
			state: &state,
			laterTurns: laterTurns[...],
			hasEarlierHistory: hasEarlierHistory,
			hasLaterChanges: hasLaterLiveChanges || laterTurns.contains
			{
				$0.items.contains(where: isCompletedEdit)
			}
		)
	}

	private static func parse(_ changes: [FileChange]) -> ReviewParsedChanges
	{
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
		return ReviewParsedChanges(
			changes: changes,
			identities: changes.map(changeIdentity),
			files: files
		)
	}

	private static func analyze(
		threadID: String,
		turn: CodexTurn,
		parsed: ReviewParsedChanges,
		state: inout Fingerprint,
		laterTurns: ArraySlice<CodexTurn>,
		hasEarlierHistory: Bool,
		hasLaterChanges: Bool
	) -> ReviewTurn
	{
		var laterEdits = Array(
			repeating: false,
			count: turn.items.count
		)
		var encounteredEdit = false
		for index in turn.items.indices.reversed()
		{
			laterEdits[index] = encounteredEdit
			encounteredEdit = encounteredEdit || isCompletedEdit(turn.items[index])
		}
		var changeIndex = 0
		var validations: [ReviewValidation] = []
		for (index, item) in turn.items.enumerated()
		{
			if item.type == "fileChange", item.status == "completed"
			{
				for _ in item.changes
				{
					state.append(parsed.identities[changeIndex])
					changeIndex += 1
				}
			}
			guard item.type == "commandExecution", let command = item.command
			else
			{
				continue
			}
			validations.append(validation(
				threadID: threadID,
				turnID: turn.id,
				item: item,
				command: command,
				isOutdated: laterEdits[index] || hasLaterChanges,
				stateID: state.identity,
				hasEarlierHistory: hasEarlierHistory
			))
		}

		let finalState = state.identity
		if !parsed.files.isEmpty
		{
			validations.append(contentsOf: validationsBeforeNextEdit(
				in: laterTurns,
				threadID: threadID,
				stateID: finalState,
				hasEarlierHistory: hasEarlierHistory,
				hasLaterChanges: hasLaterChanges
			))
		}

		return ReviewTurn(
			threadID: threadID,
			turnID: turn.id,
			files: parsed.files,
			validations: validations,
			codeStateID: finalState,
			hasUnknownEarlierHistory: hasEarlierHistory
		)
	}

	private static func validationsBeforeNextEdit(
		in turns: ArraySlice<CodexTurn>,
		threadID: String,
		stateID: String,
		hasEarlierHistory: Bool,
		hasLaterChanges: Bool
	) -> [ReviewValidation]
	{
		var validations: [ReviewValidation] = []
		for turn in turns
		{
			for item in turn.items
			{
				if isCompletedEdit(item)
				{
					return validations
				}
				guard item.type == "commandExecution", let command = item.command
				else
				{
					continue
				}
				validations.append(validation(
					threadID: threadID,
					turnID: turn.id,
					item: item,
					command: command,
					isOutdated: hasLaterChanges,
					stateID: stateID,
					hasEarlierHistory: hasEarlierHistory
				))
			}
		}
		return validations
	}

	private static func validation(
		threadID: String,
		turnID: String,
		item: CodexItem,
		command: String,
		isOutdated: Bool,
		stateID: String,
		hasEarlierHistory: Bool
	) -> ReviewValidation
	{
		ReviewValidation(
			threadID: threadID,
			turnID: turnID,
			itemID: item.id,
			command: command,
			cwd: item.cwd,
			output: item.output,
			exitCode: item.exitCode,
			outcome: commandOutcome(for: item),
			currency: isOutdated ? .outdated : .uncertain,
			codeStateID: stateID,
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

	private static func isCompletedEdit(_ item: CodexItem) -> Bool
	{
		item.type == "fileChange" && item.status == "completed" && !item.changes.isEmpty
	}

	private static func sameChanges(
		_ lhs: [FileChange],
		_ rhs: [FileChange]
	) -> Bool
	{
		guard lhs.count == rhs.count
		else
		{
			return false
		}
		return zip(
			lhs,
			rhs
		).allSatisfy
		{
			left, right in
			// String equality permits canonical Unicode equivalents; fingerprints use UTF-8.
			left.path.utf8.elementsEqual(right.path.utf8)
				&& left.kind.utf8.elementsEqual(right.kind.utf8)
				&& samePath(
					left.movePath,
					right.movePath
				)
				&& left.diff.utf8.elementsEqual(right.diff.utf8)
		}
	}

	private static func samePath(
		_ lhs: String?,
		_ rhs: String?
	) -> Bool
	{
		switch (lhs, rhs)
		{
		case (nil, nil): return true
		case (.some(let left), .some(let right)): return left.utf8.elementsEqual(right.utf8)
		default: return false
		}
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

	private static func historyFingerprint(
		threadID: String,
		hasEarlierHistory: Bool
	)
		-> Fingerprint
	{
		var state = Fingerprint()
		state.append(threadID)
		state.append(hasEarlierHistory ? "earlier-history-not-loaded" : "loaded-history")
		return state
	}

	private static func changeIdentity(_ change: FileChange) -> String
	{
		"\(change.path)\u{0}\(change.movePath ?? "")\u{0}\(change.kind)\u{0}\(change.diff)"
	}

	/// Deterministic FNV-1a over UTF-8; local identity only, not a security digest.
	private static func fingerprint(_ parts: [String]) -> String
	{
		var state = Fingerprint()
		for part in parts
		{
			state.append(part)
		}
		return state.identity
	}

	private struct Fingerprint
	{
		private var value: UInt64 = 14_695_981_039_346_656_037

		mutating func append(_ part: String)
		{
			for byte in part.utf8
			{
				value = (value ^ UInt64(byte)) &* 1_099_511_628_211
			}
			value = (value ^ 0xff) &* 1_099_511_628_211
		}

		var identity: String
		{
			String(
				value,
				radix: 16
			)
		}
	}
}
