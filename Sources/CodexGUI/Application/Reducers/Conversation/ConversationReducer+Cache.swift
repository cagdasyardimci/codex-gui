import Foundation

extension ConversationReducer
{
	static func touchTurn(
		_ turnID: String,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		model.conversations.cacheAccessCounter += 1
		model.conversations.turnReferenceIndices[threadID]?.access[turnID] =
			model.conversations.cacheAccessCounter
	}

	static func cachePreview(
		_ turn: CodexTurn,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		let source = ConversationTurnSummary.make(from:
			ConversationContentReducer.entries(for: [turn])).first
			?? ConversationTurnSummary(
				turnID: turn.id,
				entryID: turn.id + ":reference",
				title: "Turn",
				reply: "No text preview is available."
			)
		let summary = ConversationTurnSummary(
			turnID: source.turnID,
			entryID: source.entryID,
			title: String(source.title.prefix(160)),
			reply: String(source.reply.prefix(800))
		)
		model.conversations.cacheAccessCounter += 1
		model.conversations.turnReferenceIndices[threadID]?.previews[turn.id] = summary
		model.conversations.turnReferenceIndices[threadID]?.previewAccess[turn.id] =
			model.conversations.cacheAccessCounter
		if ConversationCachePolicy.cost(turn) <= ConversationCachePolicy.hoverBytes,
			turn.status == "completed", turn.itemsAreComplete
		{
			model.conversations.turnReferenceIndices[threadID]?.previewTurns[turn.id] = turn
			model.conversations.turnReferenceIndices[threadID]?.previewCachedAt[turn.id] = model
				.conversations.cacheTime
		}
	}

	static func enforceCacheLimits(
		model: inout WorkspaceModel,
		now: Date? = nil
	)
	{
		let now = now ?? model.conversations.cacheTime
		let threads = Array(model.conversations.turnReferenceIndices.keys)
		for threadID in threads
		{
			guard var index = model.conversations.turnReferenceIndices[threadID]
			else
			{
				continue
			}
			for turnID in Array(index.previewTurns.keys)
			{
				if now.timeIntervalSince(index.previewCachedAt[turnID] ?? .distantPast)
					>= ConversationCachePolicy.hoverLifetime
				{
					index.previewTurns.removeValue(forKey: turnID)
					index.previewCachedAt.removeValue(forKey: turnID)
				}
			}
			model.conversations.turnReferenceIndices[threadID] = index
		}
		// Preview-only full bodies are evicted before transcript content.
		var hot = threads.flatMap
		{
			threadID in
			(model.conversations.turnReferenceIndices[threadID]?.previewTurns ?? [:]).map
			{
				(
					threadID,
					$0.key,
					ConversationCachePolicy.cost($0.value),
					model.conversations.turnReferenceIndices[threadID]?.previewCachedAt[$0.key]
						?? .distantPast
				)
			}
		}.sorted
		{
			$0.3 < $1.3
		}
		while hot.count > ConversationCachePolicy.maximumHoverTurns
			|| hot.reduce(
				0,
				{
					$0 + $1.2
				}
			) > ConversationCachePolicy.hoverBytes
		{
			let removed = hot.removeFirst()
			model.conversations.turnReferenceIndices[removed.0]?.previewTurns[removed.1] = nil
			model.conversations.turnReferenceIndices[removed.0]?.previewCachedAt[removed.1] = nil
		}
		var previews = threads.flatMap
		{
			threadID in
			(model.conversations.turnReferenceIndices[threadID]?.previews ?? [:]).map
			{
				(
					threadID,
					$0.key,
					ConversationCachePolicy.cost($0.value),
					model.conversations.turnReferenceIndices[threadID]?.previewAccess[$0.key] ?? 0
				)
			}
		}.sorted
		{
			$0.3 < $1.3
		}
		while previews.count > ConversationCachePolicy.maximumPreviews
			|| previews.reduce(
				0,
				{
					$0 + $1.2
				}
			) > ConversationCachePolicy.previewBytes
		{
			let removed = previews.removeFirst()
			model.conversations.turnReferenceIndices[removed.0]?.previews[removed.1] = nil
			model.conversations.turnReferenceIndices[removed.0]?.previewAccess[removed.1] = nil
		}
		for threadID in threads
		{
			let errors = model.conversations.turnReferenceIndices[threadID]?.previewErrors ?? [:]
			if errors.count > ConversationCachePolicy.maximumPreviews
			{
				for turnID in errors.keys.sorted().prefix(errors.count
					- ConversationCachePolicy.maximumPreviews)
				{
					model.conversations.turnReferenceIndices[threadID]?.previewErrors[turnID] = nil
				}
			}
		}
		var candidates: [(String, String, Int, Int)] = []
		var costs: [String: Int] = [:]
		var counts: [String: Int] = [:]
		for (key, content) in model.conversations.content
		{
			guard let threadID = key.threadID
			else
			{
				continue
			}
			let index = model.conversations.turnReferenceIndices[threadID]
			var protected = model.conversations.selectedConversation == key
				? index?.viewport.turnIDs ?? [] : []
			if model.conversations.selectedConversation == key && protected.isEmpty
			{
				protected
					.formUnion(content.loadedTurns.suffix(ConversationCachePolicy.contentPageSize)
						.map(\.id))
			}
			if let destination = index?.navigationProtection,
				model.conversations.selectedConversation == key
			{
				protected.insert(destination)
			}
			if let anchor = index?.viewport.anchorTurnID,
				model.conversations.selectedConversation == key
			{
				protected.insert(anchor)
			}
			if model.execution.activeThreadID == threadID, let live = model.execution.activeTurnID
			{
				protected.insert(live)
			}
			if let pending = model.contextNavigation.pendingJump,
				pending.context.threadID == threadID
			{
				protected.insert(pending.turnID)
			}
			counts[threadID] = content.loadedTurns.count
			for turn in content.loadedTurns
			{
				let cost = ConversationCachePolicy.cost(turn)
					+ content.entries.filter
					{
						$0.id.hasPrefix(turn.id + ":")
					}
					.reduce(0)
					{
						$0 + $1.body.utf8.count + $1.title.utf8.count
					}
				costs[threadID, default: 0] += cost
				if !protected.contains(turn.id)
				{
					candidates.append((threadID, turn.id, cost, index?.access[turn.id] ?? 0))
				}
			}
		}
		var total = costs.values.reduce(
			0,
			+
		) + hot.reduce(0)
		{
			$0 + $1.2
		}
		while total > ConversationCachePolicy.contentBytes && !hot.isEmpty
		{
			let removed = hot.removeFirst()
			model.conversations.turnReferenceIndices[removed.0]?.previewTurns[removed.1] = nil
			model.conversations.turnReferenceIndices[removed.0]?.previewCachedAt[removed.1] = nil
			total -= removed.2
		}
		var evictions: [String: Set<String>] = [:]
		for candidate in candidates.sorted(by:
			{
				$0.3 < $1.3
			})
		{
			if total > ConversationCachePolicy.contentBytes
				|| counts[candidate.0, default: 0] > ConversationCachePolicy.maximumTurnsPerChat
			{
				evictions[candidate.0, default: []].insert(candidate.1)
				counts[candidate.0, default: 0] -= 1
				total -= candidate.2
			}
		}
		model.conversations.cacheOverBudget = total > ConversationCachePolicy.contentBytes
		for (threadID, removed) in evictions
		{
			ConversationContentReducer.updateContent(
				for: threadID,
				model: &model
			)
			{
				content in
				content.loadedTurns.removeAll
				{
					removed.contains($0.id)
				}
				content.entries.removeAll
				{
					entry in
					removed
						.contains(String(entry.id.split(
							separator: ":",
							maxSplits: 1
						).first ?? ""))
				}
				for turnID in removed
				{
					content.content.turnTimings[turnID] = nil
				}
				ConversationContentReducer.reviewSourceChanged(
					content: &content,
					threadID: threadID
				)
			}
			model.conversations.contentRevisions[threadID, default: 0] += 1
		}
		refreshCacheGaps(model: &model)
	}

	static func refreshCacheGaps(model: inout WorkspaceModel)
	{
		for threadID in model.conversations.turnReferenceIndices.keys
		{
			let references = model.conversations.turnReferenceIndices[threadID]?.references ?? []
			guard !references.isEmpty,
					var content = model.conversations.content[.thread(threadID)]
			else
			{
				continue
			}
			let positions = Dictionary(uniqueKeysWithValues: references.enumerated().map
			{
				(
					$0.element.id,
					$0.offset
				)
			})
			let turns = content.loadedTurns
				.sorted
				{
					(positions[$0.id] ?? Int.max) < (positions[$1.id] ?? Int.max)
				}
			if turns.map(\.id) != content.loadedTurns.map(\.id)
			{
				let known = Set(content.loadedTurns.map(\.id))
				let provisional = content.entries.filter
				{
					!known.contains(String($0.id.split(
						separator: ":",
						maxSplits: 1
					).first ?? ""))
				}
				content.loadedTurns = turns
				content.entries = ConversationContentReducer.entries(for: turns) + provisional
			}
			var gaps: [String: Int] = [:]
			for pair in zip(
				turns,
				turns.dropFirst()
			)
			{
				if let first = positions[pair.0.id], let next = positions[pair.1.id],
					next > first + 1
				{
					gaps[pair.1.id] = next - first - 1
				}
			}
			var inserted: Set<String> = []
			var entries: [ConversationEntry] = []
			for entry in content.entries where !entry.id.hasSuffix(":cache-gap")
			{
				let turnID = String(entry.id.split(
					separator: ":",
					maxSplits: 1
				).first ?? "")
				if let count = gaps[turnID], inserted.insert(turnID).inserted
				{
					entries.append(ConversationEntry(
						id: turnID + ":cache-gap",
						kind: .notice,
						title: "More messages",
						body: "\(count) turns between these messages. Scroll here to load them."
					))
				}
				entries.append(entry)
			}
			if content.entries != entries
			{
				content.entries = entries
				model.conversations.contentRevisions[threadID, default: 0] += 1
			}
			model.conversations.content[.thread(threadID)] = content
		}
	}
}
