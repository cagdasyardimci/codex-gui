import Foundation

struct ConversationActivityRow: Equatable
{
	enum Kind: Hashable
	{
		case group, read, search, listFiles, command, image
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
	var expanded: Bool = false
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
		collapsedGroupIDs: Set<String> = [],
		expandedActivityIDs: Set<String> = []
	) -> [Self]
	{
		var rows: [Self] = []
		var pending: [ConversationEntry] = []
		var emittedTimings = Set<String>()
		func appendTiming(for entry: ConversationEntry)
		{
			let turnID = entry.id.components(separatedBy: ":").first ?? entry.id
			guard emittedTimings.insert(turnID).inserted,
					let timing = timings.first(where:
					{
						$0.turnID == turnID
					}),
					timing.startedAt != nil || timing.durationMs != nil
			else
			{
				return
			}
			rows.append(.turnStatus(timing))
		}
		func appendPendingActivityGroup()
		{
			guard let first = pending.first
			else
			{
				return
			}
			let groupID = "activity-group:\(first.id)"
			let actions = activityRows(
				for: pending,
				groupID: groupID,
				projectPath: projectPath,
				expandedActivityIDs: expandedActivityIDs
			)
			let title = activityGroupTitle(
				actions: actions,
				entries: pending
			)
			let expanded = !collapsedGroupIDs.contains(groupID)
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
		for entry in entries
		{
			if let previous = pending.last,
				previous.id.components(separatedBy: ":").first
				!= entry.id.components(separatedBy: ":").first
			{
				appendPendingActivityGroup()
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
					expanded: !collapsedGroupIDs.contains(entry.id)
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
		// Show the clock while waiting for the first canonical item of a live turn.
		for timing in timings where timing.status == "inProgress"
			&& timing.startedAt != nil && !emittedTimings.contains(timing.turnID)
		{
			rows.append(.turnStatus(timing))
		}
		return rows
	}

	private static func activityRows(
		for entries: [ConversationEntry],
		groupID: String,
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
			let metadata = command.actions
			if metadata.isEmpty
			{
				actions.append(ConversationActivityRow(
					id: entry.id,
					sourceEntryID: entry.id,
					groupID: groupID,
					kind: .command,
					title: "Ran \(preview(command.command))",
					command: command,
					expanded: expandedActivityIDs.contains(entry.id)
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
					title = "Ran \(preview(command.command))"
				}
				let filePath = kind == .read ? resolvedPath(
					action.path,
					cwd: command.cwd,
					projectPath: projectPath
				) : nil
				let needsReadTitleFallback = kind == .read && filePath == nil
				let actionTitle = needsReadTitleFallback
					? "Read " + (action.name ?? action.path ?? action.command) : title

				actions.append(ConversationActivityRow(
					id: id,
					sourceEntryID: entry.id,
					groupID: groupID,
					kind: kind,
					title: actionTitle,
					filePath: filePath,
					linkTitle: kind == .read ? action.name ?? action.path : nil,
					command: command,
					expanded: expandedActivityIDs.contains(id)
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
		if kinds.contains(.search)
		{
			summary.append("Searched files")
		}
		if kinds.contains(.listFiles)
		{
			summary.append("Listed files")
		}
		if kinds.contains(.command)
		{
			summary.append("Ran commands")
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
			let outcome: String?
			switch command.status
			{
			case "declined": outcome = "declined"
			case "interrupted", "cancelled", "stopped": outcome = "interrupted"
			case "failed": outcome = "failed"
			default: outcome = command.exitCode.map
			{
				$0 != 0 ? "failed" : nil
			} ?? nil
			}
			if let outcome
			{
				outcomes[outcome, default: 0] += 1
			}
		}
		for outcome in ["failed", "declined", "interrupted"]
		{
			if let count = outcomes[outcome]
			{
				title += " · \(count) \(outcome)"
			}
		}
		return title
	}

	private static func preview(_ command: String) -> String
	{
		command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
