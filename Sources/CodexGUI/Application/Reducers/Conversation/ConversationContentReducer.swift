import Foundation

/// Transient composition for pure mutations and selectors; the model stores each slice once.
struct ConversationProjection
{
	var content: ConversationContentModel
	let review: ConversationReviewModel
	/// Shared navigation metadata is consulted lazily only when editing-turn identity changes.
	let turnReferences: [ConversationTurnReference]
	var didReconcileReportedGitTurn = false
	var loadedTurns: [CodexTurn]
	{
		get
		{
			content.loadedTurns
		}
		set
		{
			content.loadedTurns = newValue
		}
	}
	var hasLoadedHistory: Bool
	{
		get
		{
			content.hasLoadedHistory
		}
		set
		{
			content.hasLoadedHistory = newValue
		}
	}
	var nextTurnsCursor: String?
	{
		get
		{
			content.nextTurnsCursor
		}
		set
		{
			content.nextTurnsCursor = newValue
		}
	}
	var entries: [ConversationEntry]
	{
		get
		{
			content.entries
		}
		set
		{
			content.entries = newValue
		}
		_modify
		{
			yield &content.entries
		}
	}
	var changedFiles: [ChangeFile]
	{
		get
		{
			content.changedFiles
		}
		set
		{
			content.changedFiles = newValue
		}
	}
	var diff: String
	{
		get
		{
			content.diff
		}
		set
		{
			content.diff = newValue
		}
	}
	var changesByItemID: [String: [FileChange]]
	{
		get
		{
			content.changesByItemID
		}
		set
		{
			content.changesByItemID = newValue
		}
	}
	var hasAggregateDiff: Bool
	{
		get
		{
			content.hasAggregateDiff
		}
		set
		{
			content.hasAggregateDiff = newValue
		}
	}
	var reviewTurns: [ReviewTurn]
	{
		get
		{
			review.turns
		}
	}
	var selectedReviewTurnID: String?
	{
		get
		{
			review.selectedTurnID
		}
	}
	var liveChangeTurnID: String?
	{
		get
		{
			content.liveChangeTurnID
		}
		set
		{
			content.liveChangeTurnID = newValue
		}
	}
}

/// Pure canonical conversation computation shared by accepted history and streaming actions.
@MainActor
enum ConversationContentReducer
{
	static func projection(
		_ model: WorkspaceModel,
		key: ConversationKey
	) -> ConversationProjection
	{
		ConversationProjection(
			content: model.conversations.content[key] ?? ConversationContentModel(),
			review: model.review.conversations[key] ?? ConversationReviewModel(),
			turnReferences: key.threadID.flatMap
			{
				model.conversations.turnReferenceIndices[$0]?.references
			} ?? []
		)
	}
	static func updateContent(
		for threadID: String,
		model: inout WorkspaceModel,
		_ update: (inout ConversationProjection) -> Void
	)
	{
		updateConversation(
			.thread(threadID),
			model: &model,
			update
		)
	}
	static func updateConversation(
		_ key: ConversationKey,
		model: inout WorkspaceModel,
		_ update: (inout ConversationProjection) -> Void
	)
	{
		var value = projection(
			model,
			key: key
		)
		if !value.content.hasResolvedReportedGitTurn
		{
			value.content.latestReportedGitTurn = value.content.latestReportedGitTurn
				?? ConversationReportedGitTurn.latest(in: value.loadedTurns)
			value.content.hasResolvedReportedGitTurn = true
		}
		let previousTurnCount = value.loadedTurns.count
		update(&value)
		if value.loadedTurns.count > previousTurnCount, !value.didReconcileReportedGitTurn
		{
			reconcileReportedGitTurn(content: &value)
		}
		model.conversations.content[key] = value.content
	}
	static func merge(
		_ detail: ThreadDetail,
		model: inout WorkspaceModel
	)
	{
		updateContent(
			for: detail.summary.id,
			model: &model
		)
		{
			content in
			replaceLoadedHistory(
				detail,
				content: &content
			)
			reconcileReportedGitTurn(
				content: &content,
				trustLoadedOrder: true
			)

			if content.loadedTurns.contains(where:
				{
					$0.id == content.liveChangeTurnID
						&& !ConversationTurnStatus.isRunning($0.status)
				})
			{
				content.liveChangeTurnID = nil
			}
			reviewSourceChanged(
				content: &content,
				threadID: detail.summary.id
			)
			rebuildHistoryEntriesAndChanges(
				detail.turns,
				content: &content
			)
		}
	}

	private static func replaceLoadedHistory(
		_ detail: ThreadDetail,
		content: inout ConversationProjection
	)
	{
		let observedTurnID = content.content.latestObservedGitTurnID
		let observedStatus = observedTurnID.flatMap
		{
			content.content.turnTimings[$0]
		}?
		.status
		let observedStillRunning = ConversationTurnStatus.isRunning(observedStatus)
		let historyIncludesObserved = detail.turns.contains(where:
			{
				$0.id == observedTurnID
			})
		content.loadedTurns = detail.turns
		// A read captured before an external start cannot roll its live identity back.
		if !observedStillRunning || historyIncludesObserved
		{
			content.content.latestObservedGitTurnID = detail.turns.last?.id
		}
		for turn in detail.turns
		{
			content.content.turnTimings[turn.id] = ConversationTurnTiming(
				turn: turn,
				previous: content.content.turnTimings[turn.id]
			)
		}
		content.hasLoadedHistory = true
		content.nextTurnsCursor = detail.nextTurnsCursor
	}

	private static func rebuildHistoryEntriesAndChanges(
		_ turns: [CodexTurn],
		content: inout ConversationProjection
	)
	{
		let previousActivities = Dictionary(
			uniqueKeysWithValues: content.entries.compactMap
			{
				entry -> (String, CodexSubagentActivity)? in
				guard case .subagent(let activity) = entry.activity
				else
				{
					return nil
				}
				return (entry.id, activity)
			}
		)
		content.content.localUserMessageTurnIDs.removeAll()
		content.entries = entries(for: turns).map
		{
			var entry = $0
			if case .subagent(let activity) = entry.activity
			{
				entry.activity = .subagent(activity.recordingLifecycle(
					at: nil,
					previous: previousActivities[entry.id]
				))
			}
			return entry
		}
		if let latestTurn = turns.last
		{
			applyReview(
				for: latestTurn,
				content: &content
			)
		}
		else
		{
			resetChanges(&content)
		}
	}

	static func resetChanges(_ content: inout ConversationProjection)
	{
		content.changedFiles = []
		content.diff = ""
		content.changesByItemID = [:]
		content.hasAggregateDiff = false
	}
	static func observe(
		_ event: AppServerEvent,
		model: inout WorkspaceModel,
		observedAt: Date? = nil
	)
	{
		switch event
		{
		case .turnStarted(
			let threadID,
			let turn
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				for entry in content.entries where entry.kind == .user
					&& entry.id.hasPrefix("local:")
					&& content.content.localUserMessageTurnIDs[entry.id] == nil
				{
					content.content.localUserMessageTurnIDs[entry.id] = turn.id
				}
				content.content.latestObservedGitTurnID = turn.id
				content.content.turnTimings[turn.id] = ConversationTurnTiming(
					turn: turn,
					previous: content.content.turnTimings[turn.id],
					observedAt: observedAt
				)
				resetChanges(&content)
			}
		case .turnCompleted(
			let threadID,
			let turn
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				// A late completion for an older turn must not replace a newer observed start.
				content.didReconcileReportedGitTurn = true
				let latest = content.content.latestObservedGitTurnID
				let completedTurnWasRunning = ConversationTurnStatus.isRunning(
					content.content.turnTimings[turn.id]?.status
				)
				let mayAdvanceReportedTurn = (latest == turn.id
					&& completedTurnWasRunning)
					|| (latest == nil && content.content.latestReportedGitTurn == nil)
				let latestStatus = latest.flatMap
				{
					content.content.turnTimings[$0]
				}?
				.status
				let latestIsRunning = ConversationTurnStatus.isRunning(latestStatus)
				let completedIndex = content.loadedTurns.firstIndex(where:
					{
						$0.id == turn.id
					})
				let isOlderLoadedTurn = completedIndex.map
				{
					$0 < content.loadedTurns.count - 1
				} ?? false
				if latest == nil || latest == turn.id || (!latestIsRunning && !isOlderLoadedTurn)
				{
					content.content.latestObservedGitTurnID = turn.id
				}
				content.content.turnTimings[turn.id] = ConversationTurnTiming(
					turn: turn,
					previous: content.content.turnTimings[turn.id],
					observedAt: observedAt
				)
				for item in turn.items
				{
					upsert(
						item,
						turnID: turn.id,
						content: &content,
						allowUnorderedReportedTurnAdvance: mayAdvanceReportedTurn
					)
				}
				if let index = content.loadedTurns.firstIndex(where:
					{
						$0.id == turn.id
					})
				{
					content.loadedTurns[index] = turn
				}
				else
				{
					content.loadedTurns.append(turn)
				}
				applyReview(
					for: turn,
					content: &content
				)
				reviewSourceChanged(
					content: &content,
					threadID: threadID
				)
			}

		case .itemStarted(
			let threadID,
			let turnID,
			let item
		), .itemCompleted(
			let threadID,
			let turnID,
			let item
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				let mayAdvanceReportedTurn = content.content.latestObservedGitTurnID == turnID
					&& ConversationTurnStatus.isRunning(content.content.turnTimings[turnID]?.status)
				upsert(
					item,
					turnID: turnID,
					content: &content,
					preserveProvisionalOutput: isItemStarted(event),
					allowUnorderedReportedTurnAdvance: mayAdvanceReportedTurn,
					observedAt: observedAt
				)
				updateRecordedItem(
					item,
					turnID: turnID,
					threadID: threadID,
					content: &content
				)
				if item.type == "fileChange", item.status == "completed", !item.changes.isEmpty
				{
					content.liveChangeTurnID = turnID
					reviewSourceChanged(
						content: &content,
						threadID: threadID
					)
				}
			}
		case .agentMessageDelta(
			let threadID,
			let turnID,
			let itemID,
			let text
		):
			append(
				text,
				to: "\(turnID):\(itemID)",
				kind: .agent,
				title: "Codex",
				content: &model.conversations.content[
					.thread(threadID),
					default: ConversationContentModel()
				]
			)
		case .commandOutputDelta(
			let threadID,
			let turnID,
			let itemID,
			let text
		):
			append(
				text,
				to: "\(turnID):\(itemID)",
				kind: .command,
				title: "Command",
				content: &model.conversations.content[
					.thread(threadID),
					default: ConversationContentModel()
				]
			)
		case .fileChangeUpdated(
			let threadID,
			_,
			let itemID,
			let changes
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				guard content.changesByItemID[itemID] != nil
				else
				{
					return
				}
				content.changesByItemID[itemID] = changes
				updateProvisionalReview(content: &content)
			}
		case .diffUpdated(
			let threadID,
			let turnID,
			let aggregateDiff
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				if !aggregateDiff.isEmpty
				{
					content.liveChangeTurnID = turnID
					reviewSourceChanged(
						content: &content,
						threadID: threadID
					)
				}
				content.hasAggregateDiff = true
				content.diff = aggregateDiff
				content.changedFiles =
					!content.changesByItemID.isEmpty
						? Self.displayFiles(for: content.changesByItemID)
						: Self.files(in: aggregateDiff)
			}
		default: break
		}
	}

	/// Canonical source changes notify the separate review owner without writing its projection.
	static func reviewSourceChanged(
		content: inout ConversationProjection,
		threadID: String?
	)
	{
		content.content.reviewSourceRevision += 1
	}

	static func updateRecordedItem(
		_ item: CodexItem,
		turnID: String,
		threadID: String,
		content: inout ConversationProjection
	)
	{
		guard let index = content.loadedTurns.firstIndex(where:
			{
				$0.id == turnID
			})
		else
		{
			return
		}
		let turn = content.loadedTurns[index]
		var items = turn.items
		if let itemIndex = items.firstIndex(where:
			{
				$0.id == item.id
			})
		{
			items[itemIndex] = item
		}
		else
		{
			items.append(item)
		}
		content.loadedTurns[index] = CodexTurn(
			id: turn.id,
			status: turn.status,
			items: items,
			error: turn.error,
			startedAt: turn.startedAt,
			completedAt: turn.completedAt,
			durationMs: turn.durationMs,
			itemsAreComplete: turn.itemsAreComplete
		)
		reviewSourceChanged(
			content: &content,
			threadID: threadID
		)
	}

	private static func matchingLocalUserMessage(
		_ entry: ConversationEntry,
		turnID: String,
		content: ConversationProjection
	) -> Int?
	{
		guard entry.kind == .user
		else
		{
			return nil
		}
		return content.entries.firstIndex
		{
			local in
			local.kind == .user
				&& content.content.localUserMessageTurnIDs[local.id] == turnID
				&& local.body == entry.body
				&& local.imageAttachments.map(\.path) == entry.imageAttachments.map(\.path)
				&& local.sourceReferences.count == entry.sourceReferences.count
				&& zip(
					local.sourceReferences,
					entry.sourceReferences
				).allSatisfy
				{
					$0.kind == $1.kind && $0.path == $1.path
				}
		}
	}

	static func upsert(
		_ item: CodexItem,
		turnID: String,
		content: inout ConversationProjection,
		preserveProvisionalOutput: Bool = false,
		allowUnorderedReportedTurnAdvance: Bool = false,
		observedAt: Date? = nil
	)
	{
		let id = "\(turnID):\(item.id)"
		var entry = Self.entry(
			for: item,
			id: id
		)
		let existingIndex = content.content.entryIndex(for: id)
			?? matchingLocalUserMessage(
				entry,
				turnID: turnID,
				content: content
			)
		if let index = existingIndex
		{
			content.content.localUserMessageTurnIDs.removeValue(forKey: content.entries[index].id)
		}
		if case .subagent(let activity) = entry.activity
		{
			let previous = existingIndex.flatMap
			{
				index -> CodexSubagentActivity? in
				guard case .subagent(let previous) = content.entries[index].activity
				else
				{
					return nil
				}
				return previous
			}
			entry.activity = .subagent(activity.recordingLifecycle(
				at: observedAt,
				previous: previous
			))
		}
		let hasFormattedCommandBody: Bool
		if case .command = entry.activity
		{
			hasFormattedCommandBody = true
		}
		else
		{
			hasFormattedCommandBody = false
		}
		if let index = existingIndex
		{
			if preserveProvisionalOutput, item.output == nil,
				case .command(var command) = entry.activity,
				case .command(let previous) = content.entries[index].activity
			{
				command.output = previous.output
				entry.activity = .command(command)
				entry.body = commandBody(command)
			}
			content.content.updateEntry(
				at: index,
				hasFormattedCommandBody: hasFormattedCommandBody
			)
			{
				$0 = entry
			}
		}
		else
		{
			content.content.appendEntry(
				entry,
				hasFormattedCommandBody: hasFormattedCommandBody
			)
		}
		if item.type == "fileChange"
		{
			if item.status == "completed"
			{
				recordReportedGitTurn(
					turnID,
					content: &content,
					allowUnorderedAdvance: allowUnorderedReportedTurnAdvance
				)
			}
			// Started and declined items describe proposals, not applied changes.
			content.changesByItemID[item.id] = item.status == "completed" ? item.changes : nil
			updateProvisionalReview(content: &content)
		}
	}

	static func append(
		_ fragment: String,
		to id: String,
		kind: ConversationEntryKind,
		title: String,
		content: inout ConversationContentModel
	)
	{
		if let index = content.entryIndex(for: id)
		{
			let formatsCommandBody: Bool
			if case .command(let command) = content.entries[index].activity
			{
				guard command.status == "running" || command.status == "inProgress"
				else
				{
					return
				}
				formatsCommandBody = true
			}
			else
			{
				formatsCommandBody = false
			}
			let hasFormattedCommandBody = content.formattedCommandEntries.contains(index)
			content.updateEntry(
				at: index,
				hasFormattedCommandBody: formatsCommandBody
			)
			{
				entry in
				if case .command(let command) = entry.activity
				{
					appendCommandOutput(
						fragment,
						command: command,
						hasFormattedCommandBody: hasFormattedCommandBody,
						entry: &entry
					)
				}
				else
				{
					appendMessageText(
						fragment,
						entry: &entry
					)
				}
			}
		}
		else
		{
			content.appendEntry(ConversationEntry(
				id: id,
				kind: kind,
				title: title,
				body: fragment,
				isExpandable: kind == .command,
				activity: kind == .command ? .command(ConversationCommand(
					command: "",
					cwd: nil,
					output: fragment,
					status: "running",
					exitCode: nil,
					durationMs: nil,
					actions: []
				)) : nil
			))
		}
	}

	private static func appendCommandOutput(
		_ fragment: String,
		command: ConversationCommand,
		hasFormattedCommandBody: Bool,
		entry: inout ConversationEntry
	)
	{
		let outputWasEmpty = command.output.isEmpty
		var updatedCommand = command
		updatedCommand.output += fragment
		entry.activity = .command(updatedCommand)

		if hasFormattedCommandBody
		{
			if outputWasEmpty, !fragment.isEmpty
			{
				entry.body += "\n"
			}
			entry.body += fragment
		}
		else
		{
			entry.body = commandBody(updatedCommand)
		}
		entry.isExpandable = true
	}

	private static func appendMessageText(
		_ fragment: String,
		entry: inout ConversationEntry
	)
	{
		entry.body += fragment
		let maximumCollapsedMessageCharacters = 2_000
		// Probe only the expansion threshold instead of counting the entire growing message.
		entry.isExpandable = entry.body.index(
			entry.body.startIndex,
			offsetBy: maximumCollapsedMessageCharacters + 1,
			limitedBy: entry.body.endIndex
		) != nil
	}

	static func applyReview(
		for turn: CodexTurn,
		content: inout ConversationProjection
	)
	{
		let changes = turn.items.filter
		{
			$0.type == "fileChange" && $0.status == "completed"
		}.flatMap(\.changes)
		content.changedFiles = changes.map
		{
			ChangeFile(
				path: $0.path,
				status: $0.kind
			)
		}
		content.diff = Self.diff(for: changes)
		content.changesByItemID = [:]
		content.hasAggregateDiff = false
	}

	static func updateProvisionalReview(content: inout ConversationProjection)
	{
		guard !content.hasAggregateDiff
		else
		{
			return
		}
		let changes = content.changesByItemID.keys.sorted().flatMap
		{
			content.changesByItemID[$0] ?? []
		}
		content.changedFiles = Self.displayFiles(for: content.changesByItemID)
		content.diff = Self.diff(for: changes)
	}

	static func displayFiles(for items: [String: [FileChange]]) -> [ChangeFile]
	{
		items.keys.sorted().flatMap
		{
			items[$0] ?? []
		}.map
		{
			ChangeFile(
				path: $0.path,
				status: $0.kind
			)
		}
	}

	static func entries(for turns: [CodexTurn]) -> [ConversationEntry]
	{
		turns.flatMap
		{
			turn in
			turn.items.map
			{
				item in entry(
					for: item,
					id: "\(turn.id):\(item.id)"
				)
			}
		}
	}

	static func entry(
		for item: CodexItem,
		id: String
	) -> ConversationEntry
	{
		switch item.type
		{
		case "userMessage":
			return ConversationEntry(
				id: id,
				kind: .user,
				title: "You",
				body: UserMessagePresenter.body(for: item),
				imageAttachments: item.references.filter
				{
					$0.kind == .image
				},
				sourceReferences: UserMessagePresenter.sourceReferences(for: item)
			)
		case "agentMessage":
			return ConversationEntry(
				id: id,
				kind: .agent,
				title: "Codex",
				body: item.text ?? ""
			)
		case "commandExecution":
			let command = item.command ?? "Command"
			let output = item.output ?? ""
			let body = output.isEmpty ? "$ \(command)" : "$ \(command)\n\(output)"
			return ConversationEntry(
				id: id,
				kind: .command,
				title: "Command · \(item.status ?? "running")",
				body: body,
				isExpandable: true,
				activity: .command(ConversationCommand(
					command: command,
					cwd: item.cwd,
					output: output,
					status: item.status ?? "running",
					exitCode: item.exitCode,
					durationMs: item.durationMs,
					actions: item.commandActions
				)),
				sourceActivity: item.sourceActivity
			)
		case "subAgentActivity":
			return ConversationEntry(
				id: id,
				kind: .tool,
				title: "Subagent",
				body: "",
				activity: item.subagentActivity.map
				{
					.subagent($0)
				}
			)
		case "imageView":
			return ConversationEntry(
				id: id,
				kind: .tool,
				title: "Viewed an image",
				body: item.imagePath ?? "",
				isExpandable: item.imagePath != nil,
				activity: item.imagePath.map
				{
					.image(path: $0)
				}
			)
		case "fileChange":
			let names = item.changes.map
			{
				"\($0.kind): \($0.path)"
			}.joined(separator: "\n")
			return ConversationEntry(
				id: id,
				kind: .tool,
				title: "File changes · \(item.status ?? "unconfirmed")",
				body: names,
				activity: .fileChanges(
					item.changes,
					status: item.status ?? "unconfirmed"
				)
			)
		default:
			return ConversationEntry(
				id: id,
				kind: .tool,
				title: item.type,
				body: item.text ?? item.output ?? "",
				sourceActivity: item.sourceActivity
			)
		}
	}

	static func isItemStarted(_ event: AppServerEvent) -> Bool
	{
		if case .itemStarted = event
		{
			return true
		}
		return false
	}

	static func commandBody(_ command: ConversationCommand) -> String
	{
		command.output.isEmpty ? "$ \(command.command)" :
			"$ \(command.command)\n\(command.output)"
	}

	static func timings(for content: ConversationContentModel) -> [ConversationTurnTiming]
	{
		let loadedIDs = Set(content.loadedTurns.map(\.id))
		let loaded = content.loadedTurns.map
		{
			ConversationTurnTiming(
				turn: $0,
				previous: content.turnTimings[$0.id]
			)
		}
		let provisional = content.turnTimings.values.filter
		{
			!loadedIDs.contains($0.turnID)
		}.sorted
		{
			$0.turnID < $1.turnID
		}
		return loaded + provisional
	}

	static func diff(for changes: [FileChange]) -> String
	{
		changes.map
		{
			change in
			if change.diff.hasPrefix("diff --git ")
			{
				return change.diff
			}
			return "diff --git a/\(change.path) b/\(change.path)\n\(change.diff)"
		}.joined(separator: "\n")
	}

	static func files(in aggregateDiff: String) -> [ChangeFile]
	{
		GitDiffParser.filePaths(in: aggregateDiff).map
		{
			ChangeFile(
				path: $0,
				status: "Modified"
			)
		}
	}
}
