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
	var totalThreadCount: Int
	{
		titles.count
	}

	init(_ model: WorkspaceModel)
	{
		let titles = Dictionary(
			model.conversations.threads.map
			{
				($0.id, $0.displayTitle)
			},
			uniquingKeysWith:
			{
				first, _ in first
			}
		)
		self.titles = titles
		var histories: [String: History] = [:]
		for (key, content) in model.conversations.content
		{
			guard case .thread(let id) = key, titles[id] != nil, content.hasLoadedHistory
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
	}

	static func == (
		left: MessageSearchIndexSource,
		right: MessageSearchIndexSource
	) -> Bool
	{
		guard left.histories == right.histories,
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
