import Foundation

/// Applies the same identity-based ordering to local and acknowledged server queues.
enum ComposerQueueOrdering
{
	static func isPermutation(
		_ ids: [UUID],
		of messages: [QueuedComposerMessage]
	) -> Bool
	{
		ids.count == messages.count && Set(ids) == Set(messages.map(\.id))
	}

	static func reordered(
		_ messages: [QueuedComposerMessage],
		by ids: [UUID]
	) -> [QueuedComposerMessage]
	{
		let mapping = Dictionary(uniqueKeysWithValues: messages.map
		{
			($0.id, $0)
		})
		return ids.compactMap
		{
			mapping[$0]
		}
	}
}
