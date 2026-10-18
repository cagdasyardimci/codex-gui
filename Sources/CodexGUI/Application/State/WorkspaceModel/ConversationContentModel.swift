import Foundation

/// Value content replaces the legacy reference container when conversation ownership moves.
/// Canonical turns and provisional streaming entries are distinct observations, not two writers.
struct ConversationContentModel
{
	var loadedTurns: [CodexTurn] = []
	{
		didSet
		{
			loadedUserReferences = ConversationHistoryReferences.collect(from: loadedTurns)
			loadedHistoryRevision += 1
			turnPayloadCosts = nil
		}
	}
	/// Canonical references are stable while provisional entries stream.
	/// Memberwise initialization bypasses observers, so selectors can derive an uncached value.
	private(set) var loadedUserReferences: [UserMessageReference]?
	/// Searchable history changes independently of provisional streaming entries.
	private(set) var loadedHistoryRevision = 0
	private(set) var turnPayloadCosts: ConversationTurnPayloadCosts?
	/// The latest actual source turn observed independently of local execution ownership.
	var latestObservedGitTurnID: String?
	/// Editing identity survives transcript payload eviction.
	var latestReportedGitTurn: ConversationReportedGitTurn?
	var hasResolvedReportedGitTurn = false
	var turnTimings: [String: ConversationTurnTiming] = [:]
	var hasLoadedHistory = false
	{
		didSet
		{
			if hasLoadedHistory != oldValue
			{
				loadedHistoryRevision += 1
			}
		}
	}
	var nextTurnsCursor: String?
	{
		didSet
		{
			if nextTurnsCursor != oldValue
			{
				loadedHistoryRevision += 1
			}
		}
	}
	/// Local user rows are matched only to the turn that accepted them.
	var localUserMessageTurnIDs: [String: String] = [:]
	var entries: [ConversationEntry] = []
	{
		didSet
		{
			entryIndices = nil
			formattedCommandEntries = []
			entryPayloadRevision += 1
			entryPayloadCosts = nil
		}
	}
	/// Direct replacement and memberwise initialization rebuild the first-match lookup lazily.
	private(set) var entryIndices: [String: Int]?
	private(set) var entryPayloadRevision = 0
	private(set) var entryPayloadCosts: ConversationEntryPayloadCosts?
	/// Indexed mutations retain formatting knowledge; other writes must canonicalize it again.
	private(set) var formattedCommandEntries: Set<Int> = []
	var changedFiles: [ChangeFile] = []
	var diff = ""
	var changesByItemID: [String: [FileChange]] = [:]
	var hasAggregateDiff = false
	var liveChangeTurnID: String?
	var reviewSourceRevision = 0

	mutating func cachedTurnPayloadCosts() -> ConversationTurnPayloadCosts
	{
		if turnPayloadCosts == nil
		{
			turnPayloadCosts = ConversationTurnPayloadCosts(turns: loadedTurns)
		}
		return turnPayloadCosts!
	}

	mutating func cachedEntryPayloadCosts() -> ConversationEntryPayloadCosts
	{
		if entryPayloadCosts == nil
		{
			entryPayloadCosts = ConversationEntryPayloadCosts(entries: entries)
		}
		return entryPayloadCosts!
	}

	mutating func entryIndex(for id: String) -> Int?
	{
		if entryIndices == nil
		{
			var indices: [String: Int] = [:]
			for (index, entry) in entries.enumerated() where indices[entry.id] == nil
			{
				indices[entry.id] = index
			}
			entryIndices = indices
		}
		return entryIndices?[id]
	}

	mutating func updateEntry(
		at index: Int,
		hasFormattedCommandBody: Bool = false,
		_ update: (inout ConversationEntry) -> Void
	)
	{
		let id = entries[index].id
		let indices = entryIndices
		var payloadCosts = entryPayloadCosts
		let previousCost = payloadCosts.map
		{
			_ in ConversationEntryPayloadCosts.cost(entries[index])
		}
		var formattedEntries = formattedCommandEntries
		update(&entries[index])
		if let previousCost
		{
			payloadCosts?.replace(
				previousCost,
				with: entries[index]
			)
			entryPayloadCosts = payloadCosts
		}
		if entries[index].id == id
		{
			entryIndices = indices
		}
		if hasFormattedCommandBody
		{
			if !formattedEntries.contains(index)
			{
				formattedEntries.insert(index)
			}
		}
		else if formattedEntries.contains(index)
		{
			formattedEntries.remove(index)
		}
		formattedCommandEntries = formattedEntries
	}

	mutating func appendEntry(
		_ entry: ConversationEntry,
		hasFormattedCommandBody: Bool = false
	)
	{
		let index = entries.count
		var indices = entryIndices
		var payloadCosts = entryPayloadCosts
		var formattedEntries = formattedCommandEntries
		entries.append(entry)
		payloadCosts?.append(entry)
		entryPayloadCosts = payloadCosts
		if indices?[entry.id] == nil
		{
			indices?[entry.id] = index
		}
		entryIndices = indices
		if hasFormattedCommandBody
		{
			formattedEntries.insert(index)
		}
		formattedCommandEntries = formattedEntries
	}
}
