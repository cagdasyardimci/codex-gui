import Foundation

struct ConversationActivityRow: Equatable
{
	enum Kind: Hashable
	{
		case group, read, search, listFiles, command, image, subagent
	}
	let id: String
	let sourceEntryID: String
	let groupID: String
	let kind: Kind
	let title: String
	var filePath: String? = nil
	var linkTitle: String? = nil
	var imagePath: String? = nil
	var command: ConversationCommand? = nil
	var subagents: [CodexSubagentActivity] = []
	var expanded: Bool = false
	var isGroupedAction = false
}

enum ConversationTranscriptRow: Equatable
{
	case message(ConversationEntry)
	case activity(ConversationActivityRow)
	case turnStatus(ConversationTurnTiming)

	var id: String
	{
		switch self
		{
		case .message(let entry): entry.id
		case .activity(let row): row.id
		case .turnStatus(let timing): "timing:\(timing.turnID)"
		}
	}
	var sourceEntryID: String?
	{
		switch self
		{
		case .message(let entry): entry.id
		case .activity(let row): row.sourceEntryID
		case .turnStatus: nil
		}
	}

	static func make(
		entries: [ConversationEntry],
		timings: [ConversationTurnTiming] = [],
		projectPath: String?,
		expandedGroupIDs: Set<String> = [],
		collapsedImageIDs: Set<String> = [],
		expandedActivityIDs: Set<String> = [],
		preparedNetChanges: [String: ConversationNetFileChangePreparation.Prepared] = [:]
	) -> [Self]
	{
		var rows: [Self] = []
		var pending: [ConversationEntry] = []
		var pendingChanges: [ConversationEntry] = []
		var emittedTimings = Set<String>()
		var timingsByTurnID: [String: ConversationTurnTiming] = [:]
		timingsByTurnID.reserveCapacity(timings.count)
		for timing in timings where timingsByTurnID[timing.turnID] == nil
		{
			timingsByTurnID[timing.turnID] = timing
		}

		func appendTiming(for entry: ConversationEntry)
		{
			let turnID = ConversationEntryIdentity.turnIDWithFallback(entry.id)
			guard emittedTimings.insert(turnID).inserted,
					let timing = timingsByTurnID[turnID],
					timing.startedAt != nil || timing.durationMs != nil
			else
			{
				return
			}
			rows.append(.turnStatus(timing))
		}
		func appendPendingActivityGroup()
		{
			guard let first = pending.first, case .command(let firstCommand) = first.activity
			else
			{
				return
			}
			let groupID = "activity-group:\(first.id)"
			let isGrouped = pending.count > 1 || firstCommand.actions.count > 1
			let actions = activityRows(
				for: pending,
				groupID: groupID,
				isGrouped: isGrouped,
				projectPath: projectPath,
				expandedActivityIDs: expandedActivityIDs
			)
			// A single action is already its own expandable header.
			if !isGrouped
			{
				rows.append(.activity(actions[0]))
				pending.removeAll()
				return
			}
			let title = activityGroupTitle(
				actions: actions,
				entries: pending
			)
			let expanded = expandedGroupIDs.contains(groupID)
			rows.append(.activity(ConversationActivityRow(
				id: groupID,
				sourceEntryID: first.id,
				groupID: groupID,
				kind: .group,
				title: title,
				expanded: expanded
			)))
			if expanded
			{
				rows.append(contentsOf: actions.map(Self.activity))
			}
			pending.removeAll()
		}
		func appendPendingChanges()
		{
			guard let first = pendingChanges.first
			else
			{
				return
			}
			defer
			{
				pendingChanges.removeAll()
			}
			let turnID = ConversationEntryIdentity.turnIDWithFallback(first.id)
			guard ConversationTurnStatus.isTerminal(timingsByTurnID[turnID]?.status)
			else
			{
				return
			}
			let completedChanges = pendingChanges.flatMap
			{
				entry -> [FileChange] in
				if case .fileChanges(
					let changes,
					let status
				) = entry.activity,
					status == "completed"
				{
					return ReportedRepositoryFileChanges.filter(
						changes,
						repositoryRoot: projectPath
					)
				}
				return []
			}
			let reportedMerged: [FileChange]
			if let prepared = preparedNetChanges[turnID], prepared.matches(completedChanges)
			{
				reportedMerged = prepared.changes
			}
			else
			{
				// Keep reported edits visible if preparation is missing or no longer matches.
				reportedMerged = completedChanges
			}
			let merged = ReportedRepositoryFileChanges.filter(
				reportedMerged,
				repositoryRoot: projectPath
			)
			var emittedCompletedChanges = false
			for entry in pendingChanges
			{
				if case .fileChanges(
					_,
					let status
				) = entry.activity, status == "completed"
				{
					guard !emittedCompletedChanges, !merged.isEmpty
					else
					{
						continue
					}
					emittedCompletedChanges = true
					// Keep the summary distinct from tool entries hidden by work folding.
					rows.append(.message(ConversationEntry(
						id: "\(turnID):file-change-summary",
						kind: entry.kind,
						title: entry.title,
						body: merged.map(\.path).joined(separator: "\n"),
						activity: .fileChanges(
							merged,
							status: "completed"
						)
					)))
					continue
				}
				if case .fileChanges(
					let changes,
					let status
				) = entry.activity
				{
					let visibleChanges = ReportedRepositoryFileChanges.filter(
						changes,
						repositoryRoot: projectPath
					)
					guard !visibleChanges.isEmpty
					else
					{
						continue
					}
					rows.append(.message(ConversationEntry(
						id: entry.id,
						kind: entry.kind,
						title: entry.title,
						body: visibleChanges.map(\.path).joined(separator: "\n"),
						activity: .fileChanges(
							visibleChanges,
							status: status
						)
					)))
				}
			}
		}
		for entry in entries
		{
			if let previous = pendingChanges.last,
				ConversationEntryIdentity.turnIDWithFallback(previous.id)
				!= ConversationEntryIdentity.turnIDWithFallback(entry.id)
			{
				appendPendingActivityGroup()
				appendPendingChanges()
			}
			if entry.activity.isFileChange
			{
				appendPendingActivityGroup()
				appendTiming(for: entry)
				pendingChanges.append(entry)
				continue
			}
			if let previous = pending.last,
				ConversationEntryIdentity.turnIDWithFallback(previous.id)
				!= ConversationEntryIdentity.turnIDWithFallback(entry.id)
			{
				appendPendingActivityGroup()
			}
			// Invisible protocol items must not split adjacent visible commands.
			if entry.kind == .tool, entry.activity == nil,
				entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			{
				appendTiming(for: entry)
				continue
			}
			if case .command = entry.activity
			{
				if pending.isEmpty
				{
					appendTiming(for: entry)
				}
				pending.append(entry)
				continue
			}
			appendPendingActivityGroup()
			if entry.kind != .user
			{
				appendTiming(for: entry)
			}
			if case .image(let path) = entry.activity
			{
				rows.append(.activity(ConversationActivityRow(
					id: entry.id,
					sourceEntryID: entry.id,
					groupID: entry.id,
					kind: .image,
					title: "Viewed an image",
					imagePath: resolvedPath(
						path,
						cwd: nil,
						projectPath: projectPath
					),
					expanded: !collapsedImageIDs.contains(entry.id)
				)))
			}
			else if case .subagent(let agent) = entry.activity
			{
				rows.append(.activity(ConversationSubagentRows.row(
					id: entry.id,
					agents: [agent]
				)))
			}
			else if entry.kind != .tool || !entry.body
				.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			{
				rows.append(.message(entry))
				if entry.kind == .user
				{
					appendTiming(for: entry)
				}
			}
		}
		appendPendingActivityGroup()
		appendPendingChanges()
		// Show the clock while waiting for the first canonical item of a live turn.
		for timing in timings where timing.status == "inProgress"
			&& timing.startedAt != nil && !emittedTimings.contains(timing.turnID)
		{
			rows.append(.turnStatus(timing))
		}
		return ConversationSubagentRows.group(rows)
	}

	static func turnEntryIDs(
		entries: [ConversationEntry],
		timings: [ConversationTurnTiming]
	) -> (work: [String: Set<String>], replies: Set<String>)
	{
		let terminalTimings = timings.filter
		{
			ConversationTurnStatus.isTerminal($0.status)
		}
		let terminalTurns = Set(terminalTimings.map(\.turnID))
		let collapsibleTurns = Set(terminalTimings.filter
		{
			$0.startedAt != nil || $0.durationMs != nil
		}.map(\.turnID))
		var work: [String: Set<String>] = [:]
		var replies: [String: String] = [:]
		for entry in entries.reversed()
		{
			let turnID = ConversationEntryIdentity.turnIDWithFallback(entry.id)
			guard terminalTurns.contains(turnID), entry.kind != .user, entry.kind != .notice
			else
			{
				continue
			}
			if collapsibleTurns.contains(turnID)
			{
				work[turnID, default: []].insert(entry.id)
			}
			if entry.kind == .agent, replies[turnID] == nil,
				!entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			{
				// Display the same final nonempty reply that receives the turn's actions.
				replies[turnID] = entry.id
			}
		}
		for (turnID, replyID) in replies
		{
			work[turnID]?.remove(replyID)
		}
		return (
			work.filter
			{
				!$0.value.isEmpty
			},
			Set(replies.values.filter
			{
				ConversationEntryIdentity($0) != nil
			})
		)
	}

	static func collapsingWork(
		in rows: [Self],
		workEntryIDs: [String: Set<String>],
		expandedTurnIDs: Set<String>
	) -> [Self]
	{
		let hiddenIDs = hiddenWorkEntryIDs(
			workEntryIDs: workEntryIDs,
			expandedTurnIDs: expandedTurnIDs
		)
		return rows.filter
		{
			$0.sourceEntryID.map
			{
				!hiddenIDs.contains($0)
			} ?? true
		}
	}

	static func hiddenWorkEntryIDs(
		workEntryIDs: [String: Set<String>],
		expandedTurnIDs: Set<String>
	) -> Set<String>
	{
		workEntryIDs.reduce(into: Set<String>())
		{
			if !expandedTurnIDs.contains($1.key)
			{
				$0.formUnion($1.value)
			}
		}
	}

	private static func activityRows(
		for entries: [ConversationEntry],
		groupID: String,
		isGrouped: Bool,
		projectPath: String?,
		expandedActivityIDs: Set<String>
	) -> [ConversationActivityRow]
	{
		var actions: [ConversationActivityRow] = []
		for entry in entries
		{
			guard case .command(let command) = entry.activity
			else
			{
				continue
			}
			let outcome = ConversationCommandOutcome(command)
			let metadata = command.actions
			if metadata.isEmpty
			{
				actions.append(ConversationActivityRow(
					id: entry.id,
					sourceEntryID: entry.id,
					groupID: groupID,
					kind: .command,
					title: commandTitle(
						command.command,
						outcome: outcome,
						isGrouped: isGrouped
					),
					command: command,
					expanded: expandedActivityIDs.contains(entry.id),
					isGroupedAction: isGrouped
				))
			}
			for (index, action) in metadata.enumerated()
			{
				let id = index == 0 ? entry.id : "\(entry.id):action:\(index)"
				let kind: ConversationActivityRow.Kind
				let title: String
				switch action.kind
				{
				case .read:
					kind = .read
					title = "Read"
				case .search:
					kind = .search
					title = "Searched for \(action.query ?? action.command)"
						+ (action.path.map
						{
							" in \($0)"
						} ?? "")
				case .listFiles:
					kind = .listFiles
					title = "Listed files" + (action.path.map
					{
						" in \($0)"
					} ?? "")
				case .unknown:
					kind = .command
					title = commandTitle(
						action.command,
						outcome: outcome,
						isGrouped: isGrouped
					)
				}
				let filePath = kind == .read ? resolvedPath(
					action.path,
					cwd: command.cwd,
					projectPath: projectPath
				) : nil
				let needsReadTitleFallback = kind == .read && filePath == nil
				let actionTitle: String
				if case .failed = outcome, kind != .command
				{
					actionTitle = commandTitle(
						action.command,
						outcome: outcome,
						isGrouped: isGrouped
					)
				}
				else
				{
					actionTitle = needsReadTitleFallback
						? "Read " + (action.name ?? action.path ?? action.command) : title
				}

				actions.append(ConversationActivityRow(
					id: id,
					sourceEntryID: entry.id,
					groupID: groupID,
					kind: kind,
					title: actionTitle,
					filePath: filePath,
					linkTitle: kind == .read ? action.name ?? action.path : nil,
					command: command,
					expanded: expandedActivityIDs.contains(id),
					isGroupedAction: isGrouped
				))
			}
		}
		return actions
	}

	private static func activityGroupTitle(
		actions: [ConversationActivityRow],
		entries: [ConversationEntry]
	) -> String
	{
		let kinds = Set(actions.map(\.kind))
		var summary: [String] = []
		if kinds.contains(.read)
		{
			summary.append("Read files")
		}
		else if kinds.contains(.search)
		{
			summary.append("Searched files")
		}
		else if kinds.contains(.listFiles)
		{
			summary.append("Listed files")
		}
		let commandCount = Set(actions.lazy.filter
		{
			$0.kind == .command
		}.map(\.sourceEntryID))
			.count
		if commandCount > 0
		{
			summary.append(commandCount == 1 ? "Ran a command" : "Ran commands")
		}
		var title = summary.enumerated()
			.map
			{
				$0.offset == 0 ? $0.element : $0.element.lowercased()
			}
			.joined(separator: ", ")
		var outcomes: [String: Int] = [:]
		for entry in entries
		{
			guard case .command(let command) = entry.activity
			else
			{
				continue
			}
			if let outcome = ConversationCommandOutcome(command).groupTitle
			{
				outcomes[outcome, default: 0] += 1
			}
		}
		for outcome in ["declined", "interrupted"]
		{
			if let count = outcomes[outcome]
			{
				title += " · \(count) \(outcome)"
			}
		}
		return title
	}

	private static func commandTitle(
		_ command: String,
		outcome: ConversationCommandOutcome,
		isGrouped: Bool
	) -> String
	{
		let preview = command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
		if case .failed = outcome
		{
			return "Command failed (\(preview))"
		}
		return isGrouped ? preview : "Ran \(preview)"
	}

	private static func resolvedPath(
		_ path: String?,
		cwd: String?,
		projectPath: String?
	) -> String?
	{
		guard let path, !path.isEmpty
		else
		{
			return nil
		}
		if NSString(string: path).isAbsolutePath
		{
			return path
		}
		guard let base = cwd ?? projectPath,
				NSString(string: base).isAbsolutePath
		else
		{
			return nil
		}
		return URL(fileURLWithPath: base).appendingPathComponent(path).standardized.path
	}
}
