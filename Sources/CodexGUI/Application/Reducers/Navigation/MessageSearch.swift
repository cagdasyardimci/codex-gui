import Foundation

struct SearchableThread: Sendable
{
	let threadID: String
	let title: String
	let turns: [CodexTurn]
	/// True when the app-server has another page of earlier turns for this conversation.
	let hasEarlierTurns: Bool
}

struct MessageSearchScope: Equatable, Sendable
{
	let loadedThreadCount: Int
	let totalThreadCount: Int
	let threadsWithEarlierTurns: Int

	var isComplete: Bool
	{
		loadedThreadCount >= totalThreadCount && threadsWithEarlierTurns == 0
	}

	var canLoadMore: Bool
	{
		!isComplete
	}

	var description: String
	{
		let base = "Searching \(loadedThreadCount) of \(totalThreadCount) listed conversations"
		guard threadsWithEarlierTurns > 0
		else
		{
			return base
		}
		return "\(base); \(threadsWithEarlierTurns) have earlier turns to load"
	}
}

struct MessageSearchHit: Equatable, Identifiable, Sendable
{
	let threadID: String
	let threadTitle: String
	let turnID: String
	let itemID: String
	let itemType: String
	let snippet: String

	var id: String
	{
		"\(threadID):\(turnID):\(itemID)"
	}
}

struct MessageSearchResults: Equatable, Sendable
{
	let query: String
	let scope: MessageSearchScope
	let hits: [MessageSearchHit]
}

enum MessageSearch
{
	static func pendingResults(
		query: String,
		threads: [SearchableThread],
		totalThreadCount: Int
	) -> MessageSearchResults
	{
		MessageSearchResults(
			query: query.trimmingCharacters(in: .whitespacesAndNewlines),
			scope: MessageSearchScope(
				loadedThreadCount: threads.count,
				totalThreadCount: max(
					totalThreadCount,
					threads.count
				),
				threadsWithEarlierTurns: threads.filter(\.hasEarlierTurns).count
			),
			hits: []
		)
	}

	static func search(
		query: String,
		threads: [SearchableThread],
		totalThreadCount: Int,
		isCancelled: () -> Bool =
		{
			false
		}
	) -> MessageSearchResults
	{
		let pending = pendingResults(
			query: query,
			threads: threads,
			totalThreadCount: totalThreadCount
		)
		let searchText = pending.query
		let scope = pending.scope
		guard !searchText.isEmpty
		else
		{
			return pending
		}

		var hits: [MessageSearchHit] = []
		searchThreads: for thread in threads
		{
			for turn in thread.turns
			{
				for item in turn.items
				{
					if isCancelled()
					{
						break searchThreads
					}
					guard let matchedText = firstMatchingText(
						in: item,
						query: searchText
					)
					else
					{
						continue
					}
					hits.append(
						MessageSearchHit(
							threadID: thread.threadID,
							threadTitle: thread.title,
							turnID: turn.id,
							itemID: item.id,
							itemType: item.type,
							snippet: snippet(
								around: searchText,
								in: matchedText
							)
						)
					)
				}
			}
		}
		return MessageSearchResults(
			query: searchText,
			scope: scope,
			hits: hits
		)
	}

	private static func firstMatchingText(
		in item: CodexItem,
		query: String
	) -> String?
	{
		let messageAndCommandText = [item.text, item.command, item.output].compactMap
		{
			$0
		}
		let changedPaths = item.changes.map(\.path)
		return (messageAndCommandText + changedPaths).first
		{
			$0.range(
				of: query,
				options: [.caseInsensitive, .diacriticInsensitive]
			) != nil
		}
	}

	private static func snippet(
		around searchText: String,
		in text: String
	) -> String
	{
		guard let match = text.range(
			of: searchText,
			options: [.caseInsensitive, .diacriticInsensitive]
		)
		else
		{
			return String(text.prefix(160))
		}
		let snippetStart =
			text.index(
				match.lowerBound,
				offsetBy: -60,
				limitedBy: text.startIndex
			)
			?? text.startIndex
		let snippetEnd =
			text.index(
				match.upperBound,
				offsetBy: 100,
				limitedBy: text.endIndex
			)
			?? text.endIndex
		let prefix = snippetStart == text.startIndex ? "" : "…"
		let suffix = snippetEnd == text.endIndex ? "" : "…"
		return prefix + text[snippetStart ..< snippetEnd].replacingOccurrences(
			of: "\n",
			with: " "
		) + suffix
	}
}

struct ConversationJumpTarget: Equatable, Identifiable
{
	enum Kind: Equatable
	{
		case userRequest
		case changedFile
		case failure
	}

	let threadID: String
	let turnID: String
	let itemID: String?
	let filePath: String?
	let kind: Kind
	let title: String

	var id: String
	{
		"\(threadID):\(turnID):\(itemID ?? "turn"):\(filePath ?? ""):\(kind)"
	}
}

enum ConversationNavigation
{
	static func targets(in thread: SearchableThread) -> [ConversationJumpTarget]
	{
		var targets: [ConversationJumpTarget] = []
		for turn in thread.turns
		{
			for item in turn.items
			{
				if item.type == "userMessage", let text = item.text, !text.isEmpty
				{
					targets.append(
						ConversationJumpTarget(
							threadID: thread.threadID,
							turnID: turn.id,
							itemID: item.id,
							filePath: nil,
							kind: .userRequest,
							title: String(text.prefix(120))
						)
					)
				}
				for change in item.changes
				{
					targets.append(
						ConversationJumpTarget(
							threadID: thread.threadID,
							turnID: turn.id,
							itemID: item.id,
							filePath: change.path,
							kind: .changedFile,
							title: change.path
						)
					)
				}
				if item.status == "failed"
				{
					targets.append(
						ConversationJumpTarget(
							threadID: thread.threadID,
							turnID: turn.id,
							itemID: item.id,
							filePath: nil,
							kind: .failure,
							title: item.output ?? item.text ?? "Failed \(item.type)"
						)
					)
				}
			}
			if let error = turn.error, !error.isEmpty
			{
				targets.append(
					ConversationJumpTarget(
						threadID: thread.threadID,
						turnID: turn.id,
						itemID: nil,
						filePath: nil,
						kind: .failure,
						title: error
					)
				)
			}
		}
		return targets
	}
}
