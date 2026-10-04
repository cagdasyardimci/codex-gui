import Foundation

/// Compares the small history revisions, without traversing message contents on each token.
struct MessageSearchIndexSource: Equatable
{
	struct History: Equatable
	{
		let revision: Int
		let nextCursor: String?
	}

	let histories: [String: History]
	let titles: [String: String]
	let totalThreadCount: Int

	init(_ model: WorkspaceModel)
	{
		var histories: [String: History] = [:]
		for (key, content) in model.conversations.content
		{
			guard case .thread(let id) = key, content.hasLoadedHistory
			else
			{
				continue
			}
			histories[id] = History(
				revision: content.loadedHistoryRevision,
				nextCursor: content.nextTurnsCursor
			)
		}
		self.histories = histories
		titles = Dictionary(
			model.conversations.threads.map
			{
				($0.id, $0.name ?? $0.id)
			},
			uniquingKeysWith:
			{
				first, _ in first
			}
		)
		totalThreadCount = model.conversations.threads.count
	}

	static func == (
		left: MessageSearchIndexSource,
		right: MessageSearchIndexSource
	) -> Bool
	{
		guard left.histories == right.histories,
				left.totalThreadCount == right.totalThreadCount,
				left.titles.count == right.titles.count
		else
		{
			return false
		}
		return left.titles.allSatisfy
		{
			id, title in
			guard let otherTitle = right.titles[id]
			else
			{
				return false
			}
			// Render a renamed title's current spelling, including Unicode normalization.
			return title.utf8.elementsEqual(otherTitle.utf8)
		}
	}
}
