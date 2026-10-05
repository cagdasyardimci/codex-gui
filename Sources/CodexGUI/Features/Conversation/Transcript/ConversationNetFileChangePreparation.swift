import Foundation

/// Prepares net edits off the main actor and retains exact inputs for synchronous row assembly.
actor ConversationNetFileChangePreparation
{
	struct Source: Equatable, Sendable
	{
		let turnID: String
		let changes: [FileChange]

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			lhs.turnID.utf8.elementsEqual(rhs.turnID.utf8)
				&& ConversationNetFileChangePreparation.sameChanges(
					lhs.changes,
					rhs.changes
				)
		}
	}

	struct Prepared: Equatable, Sendable
	{
		let source: Source
		let changes: [FileChange]

		func matches(_ changes: [FileChange]) -> Bool
		{
			ConversationNetFileChangePreparation.sameChanges(
				source.changes,
				changes
			)
		}

		static func == (lhs: Self, rhs: Self) -> Bool
		{
			lhs.source == rhs.source
				&& ConversationNetFileChangePreparation.sameChanges(
					lhs.changes,
					rhs.changes
				)
		}
	}

	private let capacity: Int
	private let byteCapacity: Int
	private let merge: @Sendable ([FileChange]) async -> [FileChange]
	private var context: String?
	private var retained: [String: Prepared] = [:]
	private var generation = 0
	private(set) var retainedByteCount = 0
	var retainedItemCount: Int
	{
		retained.count
	}

	init(
		capacity: Int = 256,
		byteCapacity: Int = 8 * 1_024 * 1_024,
		merge: @escaping @Sendable ([FileChange]) async -> [FileChange] =
		{
			ConversationNetFileChanges.merge($0)
		}
	)
	{
		self.capacity = max(
			0,
			capacity
		)
		self.byteCapacity = max(
			0,
			byteCapacity
		)
		self.merge = merge
	}

	/// Only the latest accepted request commits cache entries, including net-zero edits.
	func prepare(
		_ sources: [Source],
		context: String?
	) async -> [String: Prepared]?
	{
		guard !Task.isCancelled
		else
		{
			return nil
		}
		generation += 1
		let requestGeneration = generation
		let previous = Self.sameContext(
			self.context,
			context
		) ? retained : [:]
		var results: [String: Prepared] = [:]
		var nextRetained: [String: Prepared] = [:]
		var retainedBytes = 0
		// Prefer recent turns when the resident history exceeds the retained cache budget.
		for source in sources.reversed()
		{
			guard !Task.isCancelled, requestGeneration == generation
			else
			{
				return nil
			}
			let prepared: Prepared
			if let cached = previous[source.turnID], cached.source == source
			{
				prepared = cached
			}
			else
			{
				prepared = Prepared(
					source: source,
					changes: await merge(source.changes)
				)
			}
			guard !Task.isCancelled, requestGeneration == generation
			else
			{
				return nil
			}
			results[source.turnID] = prepared
			let bytes = Self.byteCount(prepared)
			if nextRetained.count < capacity, bytes <= byteCapacity - retainedBytes
			{
				nextRetained[source.turnID] = prepared
				retainedBytes += bytes
			}
		}
		guard !Task.isCancelled, requestGeneration == generation
		else
		{
			return nil
		}
		self.context = context
		retained = nextRetained
		retainedByteCount = retainedBytes
		return results
	}

	private static func sameChanges(
		_ lhs: [FileChange],
		_ rhs: [FileChange]
	) -> Bool
	{
		lhs.count == rhs.count && zip(
			lhs,
			rhs
		).allSatisfy
		{
			left, right in
			left.path.utf8.elementsEqual(right.path.utf8)
				&& left.kind.utf8.elementsEqual(right.kind.utf8)
				&& sameContext(
					left.movePath,
					right.movePath
				)
				&& left.diff.utf8.elementsEqual(right.diff.utf8)
		}
	}

	private static func sameContext(
		_ lhs: String?,
		_ rhs: String?
	) -> Bool
	{
		switch (lhs, rhs)
		{
		case (nil, nil): true
		case (let lhs?, let rhs?): lhs.utf8.elementsEqual(rhs.utf8)
		default: false
		}
	}

	private static func byteCount(_ prepared: Prepared) -> Int
	{
		prepared.source.turnID.utf8.count + 96 + changesByteCount(prepared.source.changes)
			+ changesByteCount(prepared.changes)
	}

	private static func changesByteCount(_ changes: [FileChange]) -> Int
	{
		changes.reduce(0)
		{
			$0 + $1.path.utf8.count + $1.kind.utf8.count + ($1.movePath?.utf8.count ?? 0)
				+ $1.diff.utf8.count + 96
		}
	}
}
