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
		preview: ConversationTurnPreview,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		guard preview.turnID == turn.id
		else
		{
			return
		}
		model.conversations.cacheAccessCounter += 1
		model.conversations.turnReferenceIndices[threadID]?.previews[turn.id] = preview
		model.conversations.turnReferenceIndices[threadID]?.previewAccess[turn.id] =
			model.conversations.cacheAccessCounter
		let turnBytes = ConversationCachePolicy.cost(turn)
		if turnBytes <= ConversationCachePolicy.hoverBytes,
			turn.status == "completed", turn.itemsAreComplete,
			model.conversations.content[.thread(threadID)]?.loadedTurns.contains(where:
			{
				$0.id == turn.id
			}) != true
		{
			model.conversations.turnReferenceIndices[threadID]?.previewTurns[turn.id] = turn
			model.conversations.turnReferenceIndices[threadID]?.previewCachedAt[turn.id] = model
				.conversations.cacheTime
			model.conversations.cacheAccounting.recordHover(
				threadID: threadID,
				turnID: turn.id,
				bytes: turnBytes
			)
		}
		else
		{
			removeHover(
				threadID,
				turnID: turn.id,
				model: &model
			)
		}
	}

	/// Streaming calls synchronize only the changed conversation and skip unchanged previews.
	static func enforceCacheLimits(
		model: inout WorkspaceModel,
		now: Date? = nil,
		updating threadIDs: Set<String>? = nil,
		includePreviews: Bool = true
	)
	{
		let shouldInitializeWorkspace =
			!model.conversations.cacheAccounting.hasSynchronizedWorkspace
		let shouldSynchronizeWorkspace = threadIDs == nil || shouldInitializeWorkspace
		let synchronizedThreadIDs = shouldSynchronizeWorkspace
			? Set(model.conversations.content.keys.compactMap(\.threadID)) : threadIDs ?? []
		if shouldSynchronizeWorkspace
		{
			for threadID in model.conversations.cacheAccounting.content.keys
				where model.conversations.content[.thread(threadID)] == nil
			{
				model.conversations.cacheAccounting.remove(threadID: threadID)
			}
		}
		for threadID in synchronizedThreadIDs
		{
			synchronizeCacheCosts(
				threadID: threadID,
				model: &model
			)
			refreshCacheGaps(
				threadID: threadID,
				model: &model
			)
		}
		if includePreviews || shouldInitializeWorkspace
		{
			enforcePreviewLimits(
				model: &model,
				now: now ?? model.conversations.cacheTime
			)
		}
		model.conversations.cacheAccounting.hasSynchronizedWorkspace = true
		var total = ConversationCachePolicy.sum(
			model.conversations.cacheAccounting.totalContentBytes,
			model.conversations.cacheAccounting.totalHoverBytes
		)
		let exceedsTurnLimit = !model.conversations.cacheAccounting.chatsOverTurnLimit.isEmpty
		guard total > ConversationCachePolicy.contentBytes || exceedsTurnLimit
		else
		{
			model.conversations.cacheOverBudget = false
			return
		}
		// Hover bodies lose residency before loaded transcript content.
		for candidate in hoverCandidates(model: model)
			where total > ConversationCachePolicy.contentBytes
		{
			removeHover(
				candidate.threadID,
				turnID: candidate.turnID,
				model: &model
			)
			total -= candidate.bytes
		}
		var counts = model.conversations.cacheAccounting.content.mapValues
		{
			$0.turns.turnIDs.count
		}
		var evictions: [String: Set<String>] = [:]
		for candidate in contentCandidates(model: model)
		{
			if total > ConversationCachePolicy.contentBytes
				|| counts[candidate.threadID, default: 0] > ConversationCachePolicy
				.maximumTurnsPerChat
			{
				evictions[candidate.threadID, default: []].insert(candidate.turnID)
				counts[candidate.threadID, default: 0] -= 1
				total -= candidate.bytes
			}
		}
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
					removed.contains(ConversationEntryPayloadCosts.turnID(for: $0.id))
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
			synchronizeCacheCosts(
				threadID: threadID,
				model: &model
			)
			refreshCacheGaps(
				threadID: threadID,
				model: &model
			)
		}
		model.conversations.cacheOverBudget = ConversationCachePolicy.sum(
			model.conversations.cacheAccounting.totalContentBytes,
			model.conversations.cacheAccounting.totalHoverBytes
		) > ConversationCachePolicy.contentBytes
	}

	private struct CacheCandidate
	{
		let threadID: String
		let turnID: String
		let bytes: Int
		let access: Int
		var cachedAt: Date = .distantPast
	}

	private static func synchronizeCacheCosts(
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		guard var content = model.conversations.content[.thread(threadID)]
		else
		{
			model.conversations.cacheAccounting.remove(threadID: threadID)
			return
		}
		model.conversations.cacheAccounting.synchronize(
			threadID: threadID,
			content: &content
		)
		model.conversations.content[.thread(threadID)] = content
	}

	private static func hoverCandidates(model: WorkspaceModel) -> [CacheCandidate]
	{
		model.conversations.turnReferenceIndices.flatMap
		{
			threadID, index in
			index.previewTurns.map
			{
				turnID, turn in
				CacheCandidate(
					threadID: threadID,
					turnID: turnID,
					bytes: ConversationCachePolicy.cost(turn),
					access: 0,
					cachedAt: index.previewCachedAt[turnID] ?? .distantPast
				)
			}
		}.sorted
		{
			($0.cachedAt, $0.threadID, $0.turnID) < ($1.cachedAt, $1.threadID, $1.turnID)
		}
	}

	private static func removeHover(
		_ threadID: String,
		turnID: String,
		model: inout WorkspaceModel
	)
	{
		model.conversations.turnReferenceIndices[threadID]?.previewTurns[turnID] = nil
		model.conversations.turnReferenceIndices[threadID]?.previewCachedAt[turnID] = nil
		model.conversations.cacheAccounting.recordHover(
			threadID: threadID,
			turnID: turnID,
			bytes: nil
		)
	}

	static func discardHoverContent(
		_ turnID: String,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		removeHover(
			threadID,
			turnID: turnID,
			model: &model
		)
	}

	static func invalidateCachedTurn(
		_ turnID: String,
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		model.conversations.turnReferenceIndices[threadID]?.previews[turnID] = nil
		model.conversations.turnReferenceIndices[threadID]?.previewAccess[turnID] = nil
		removeHover(
			threadID,
			turnID: turnID,
			model: &model
		)
	}

	private static func enforcePreviewLimits(
		model: inout WorkspaceModel,
		now: Date
	)
	{
		for (threadID, index) in model.conversations.turnReferenceIndices
		{
			for turnID in index.previewTurns.keys
				where now.timeIntervalSince(index.previewCachedAt[turnID] ?? .distantPast)
				>= ConversationCachePolicy.hoverLifetime
			{
				removeHover(
					threadID,
					turnID: turnID,
					model: &model
				)
			}
		}

		enforceHoverLimits(model: &model)
		enforceTextPreviewLimits(model: &model)
	}

	private static func enforceHoverLimits(model: inout WorkspaceModel)
	{
		let cachedHoverTurns = hoverCandidates(model: model)
		var hoverBodies: [String: [String: Int]] = [:]
		for candidate in cachedHoverTurns
		{
			hoverBodies[candidate.threadID, default: [:]][candidate.turnID] = candidate.bytes
		}
		model.conversations.cacheAccounting.replaceHoverBodies(hoverBodies)
		var hoverBytes = cachedHoverTurns.reduce(0)
		{
			ConversationCachePolicy.sum(
				$0,
				$1.bytes
			)
		}
		var hoverCount = cachedHoverTurns.count
		for candidate in cachedHoverTurns
		{
			guard hoverCount > ConversationCachePolicy.maximumHoverTurns
				|| hoverBytes > ConversationCachePolicy.hoverBytes
			else
			{
				break
			}
			removeHover(
				candidate.threadID,
				turnID: candidate.turnID,
				model: &model
			)
			hoverCount -= 1
			hoverBytes -= candidate.bytes
		}
	}

	private static func enforceTextPreviewLimits(model: inout WorkspaceModel)
	{
		let previews = model.conversations.turnReferenceIndices.flatMap
		{
			threadID, index in
			index.previews.map
			{
				turnID, preview in
				CacheCandidate(
					threadID: threadID,
					turnID: turnID,
					bytes: ConversationCachePolicy.cost(preview),
					access: index.previewAccess[turnID] ?? 0
				)
			}
		}.sorted
		{
			($0.access, $0.threadID, $0.turnID) < ($1.access, $1.threadID, $1.turnID)
		}
		var previewBytes = previews.reduce(0)
		{
			ConversationCachePolicy.sum(
				$0,
				$1.bytes
			)
		}
		var previewCount = previews.count
		for candidate in previews
		{
			guard previewCount > ConversationCachePolicy.maximumPreviews
				|| previewBytes > ConversationCachePolicy.previewBytes
			else
			{
				break
			}
			model.conversations.turnReferenceIndices[candidate.threadID]?
				.previews[candidate.turnID] = nil
			model.conversations.turnReferenceIndices[candidate.threadID]?
				.previewAccess[candidate.turnID] = nil
			previewCount -= 1
			previewBytes -= candidate.bytes
		}
		for (threadID, index) in model.conversations.turnReferenceIndices
		{
			let excessErrorCount = max(
				0,
				index.previewErrors.count - ConversationCachePolicy.maximumPreviews
			)
			let errorsToRemove = index.previewErrors.keys.sorted().prefix(excessErrorCount)
			for turnID in errorsToRemove
			{
				model.conversations.turnReferenceIndices[threadID]?.previewErrors[turnID] = nil
			}
		}
	}

	private static func contentCandidates(model: WorkspaceModel) -> [CacheCandidate]
	{
		var candidates: [CacheCandidate] = []
		for (threadID, costs) in model.conversations.cacheAccounting.content
		{
			guard let content = model.conversations.content[.thread(threadID)],
					let entries = content.entryPayloadCosts
			else
			{
				continue
			}
			let protected = protectedTurns(
				threadID: threadID,
				content: content,
				model: model
			)
			let index = model.conversations.turnReferenceIndices[threadID]
			for turnID in costs.turns.turnIDs where !protected.contains(turnID)
			{
				candidates.append(CacheCandidate(
					threadID: threadID,
					turnID: turnID,
					bytes: ConversationCachePolicy.sum(
						costs.turns.byTurn[turnID, default: 0],
						entries.textByTurn[turnID, default: 0],
						costs.additionalByTurn[turnID, default: 0]
					),
					access: index?.access[turnID] ?? 0
				))
			}
		}
		return candidates.sorted
		{
			($0.access, $0.threadID, $0.turnID) < ($1.access, $1.threadID, $1.turnID)
		}
	}

	private static func protectedTurns(
		threadID: String,
		content: ConversationContentModel,
		model: WorkspaceModel
	) -> Set<String>
	{
		let index = model.conversations.turnReferenceIndices[threadID]
		var protected: Set<String> = []
		if model.conversations.selectedConversation == .thread(threadID)
		{
			protected = index?.viewport.turnIDs ?? []
			if protected.isEmpty
			{
				protected
					.formUnion(content.loadedTurns.suffix(ConversationCachePolicy.contentPageSize)
						.map(\.id))
			}
			if let destination = index?.navigationProtection
			{
				protected.insert(destination)
			}
			if let anchor = index?.viewport.anchorTurnID
			{
				protected.insert(anchor)
			}
		}
		if model.execution.activeThreadID == threadID, let live = model.execution.activeTurnID
		{
			protected.insert(live)
		}
		if let pending = model.contextNavigation.pendingJump, pending.context.threadID == threadID
		{
			protected.insert(pending.turnID)
		}
		return protected
	}

	static func refreshCacheGaps(model: inout WorkspaceModel)
	{
		for threadID in model.conversations.turnReferenceIndices.keys
		{
			refreshCacheGaps(
				threadID: threadID,
				model: &model
			)
		}
	}

	static func refreshCacheGaps(
		threadID: String,
		model: inout WorkspaceModel
	)
	{
		guard var index = model.conversations.turnReferenceIndices[threadID],
				!index.references.isEmpty,
				var content = model.conversations.content[.thread(threadID)]
		else
		{
			return
		}
		let cached = model.conversations.cacheAccounting.content[threadID]
		let entryStructureIsCached = content.entryPayloadCosts != nil && content
			.turnPayloadCosts != nil
		if entryStructureIsCached, index.referencePositions != nil,
			cached?.gapLoadedRevision == content.loadedHistoryRevision,
			cached?.gapReferenceRevision == index.referenceRevision
		{
			return
		}
		let turnIDs = content.loadedTurns.map(\.id)
		if entryStructureIsCached, index.referencePositions != nil, cached?.gapTurnIDs == turnIDs,
			cached?.gapReferenceRevision == index.referenceRevision
		{
			model.conversations.cacheAccounting.recordGaps(
				threadID: threadID,
				loadedRevision: content
					.loadedHistoryRevision,
				referenceRevision: index
					.referenceRevision,
				turnIDs: turnIDs
			)
			return
		}
		let positions = index.cachedReferencePositions()
		model.conversations.turnReferenceIndices[threadID] = index
		let turns = content.loadedTurns.enumerated().sorted
		{
			(positions[$0.element.id] ?? Int.max, $0.offset)
				< (positions[$1.element.id] ?? Int.max, $1.offset)
		}.map(\.element)
		if turns.map(\.id) != turnIDs
		{
			let known = Set(turnIDs)
			let provisional = content.entries.filter
			{
				!known.contains(ConversationEntryPayloadCosts.turnID(for: $0.id))
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
			if let first = positions[pair.0.id], let next = positions[pair.1.id], next > first + 1
			{
				gaps[pair.1.id] = next - first - 1
			}
		}
		var inserted: Set<String> = []
		var entries: [ConversationEntry] = []
		for entry in content.entries where !entry.id.hasSuffix(":cache-gap")
		{
			let turnID = ConversationEntryPayloadCosts.turnID(for: entry.id)
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
		synchronizeCacheCosts(
			threadID: threadID,
			model: &model
		)
		model.conversations.cacheAccounting.recordGaps(
			threadID: threadID,
			loadedRevision: content.loadedHistoryRevision,
			referenceRevision: index.referenceRevision,
			turnIDs: turns.map(\.id)
		)
	}
}
