import Foundation

/// Transient composition for pure mutations and selectors; the model stores each slice once.
struct ConversationProjection
{
	var content: ConversationContentModel
	let review: ConversationReviewModel
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
			review: model.review.conversations[key] ?? ConversationReviewModel()
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
		update(&value)
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
			content.loadedTurns = detail.turns
			for turn in detail.turns
			{
				content.content.turnTimings[turn.id] = ConversationTurnTiming(
					turn: turn,
					previous: content.content.turnTimings[turn.id]
				)
			}
			content.hasLoadedHistory = true
			content.nextTurnsCursor = detail.nextTurnsCursor
			if content.loadedTurns
				.contains(where:
					{
						$0.id == content.liveChangeTurnID && $0.status != "inProgress"
					})
			{
				content.liveChangeTurnID = nil
			}
			reviewSourceChanged(
				content: &content,
				threadID: detail.summary.id
			)
			content.entries = entries(for: detail.turns)
			if let latestTurn = detail.turns
				.last
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
	}
	static func resetChanges(_ content: inout ConversationProjection)
	{
		content.changedFiles = []; content.diff = ""; content.changesByItemID = [:]; content
			.hasAggregateDiff = false
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
				content.content.turnTimings[turn.id] = ConversationTurnTiming(
					turn: turn,
					previous: content.content.turnTimings[turn.id],
					observedAt: observedAt
				)
				content.changedFiles = []; content.diff = ""; content.changesByItemID = [:]
				content.hasAggregateDiff = false
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
						content: &content
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
		),
		.itemCompleted(
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
				upsert(
					item,
					turnID: turnID,
					content: &content,
					preserveProvisionalOutput: isItemStarted(event)
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
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				append(
					text,
					to: "\(turnID):\(itemID)",
					kind: .agent,
					title: "Codex",
					content: &content
				)
			}
		case .commandOutputDelta(
			let threadID,
			let turnID,
			let itemID,
			let text
		):
			updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				append(
					text,
					to: "\(turnID):\(itemID)",
					kind: .command,
					title: "Command",
					content: &content
				)
			}
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
			durationMs: turn.durationMs
		)
		reviewSourceChanged(
			content: &content,
			threadID: threadID
		)
	}

	static func upsert(
		_ item: CodexItem,
		turnID: String,
		content: inout ConversationProjection,
		preserveProvisionalOutput: Bool = false
	)
	{
		let id = "\(turnID):\(item.id)"
		var entry = Self.entry(
			for: item,
			id: id
		)
		if let index = content.entries.firstIndex(where:
			{
				$0.id == id
			})
		{
			if preserveProvisionalOutput, item.output == nil,
				case .command(var command) = entry.activity,
				case .command(let previous) = content.entries[index].activity
			{
				command.output = previous.output
				entry.activity = .command(command)
				entry.body = commandBody(command)
			}
			content.entries[index] = entry
		}
		else
		{
			content.entries.append(entry)
		}
		if item.type == "fileChange"
		{
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
		content: inout ConversationProjection
	)
	{
		if let index = content.entries.firstIndex(where:
			{
				$0.id == id
			})
		{
			if case .command(var command) = content.entries[index].activity
			{
				guard command.status == "running" || command.status == "inProgress"
				else
				{
					return
				}
				command.output += fragment
				content.entries[index].activity = .command(command)
				content.entries[index].body = commandBody(command)
				content.entries[index].isExpandable = true
			}
			else
			{
				content.entries[index].body += fragment
				content.entries[index].isExpandable = content.entries[index].body.count > 2_000
			}
		}
		else
		{
			content.entries.append(ConversationEntry(
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

	static func applyReview(
		for turn: CodexTurn,
		content: inout ConversationProjection
	)
	{
		let changes = turn.items.filter
		{
			$0.type == "fileChange" && $0.status == "completed"
		}
		.flatMap(\.changes)
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
		}
		.map
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
				body: UserMessagePresenter.body(for: item)
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
				))
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
				body: names
			)
		default:
			return ConversationEntry(
				id: id,
				kind: .tool,
				title: item.type,
				body: item.text ?? item.output ?? ""
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
		}
		.sorted
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
