import Foundation

/// Payload limits exclude AppKit rendering overhead. Visible/live turns are protected.
enum ConversationCachePolicy
{
	static let contentPageSize = 25
	static let debounceMilliseconds = 75
	static let maximumTurnsPerChat = 75
	static let contentBytes = 32 * 1024 * 1024
	static let maximumPreviews = 200
	static let previewBytes = 1024 * 1024
	static let maximumHoverTurns = 3
	static let hoverBytes = 2 * 1024 * 1024
	static let hoverLifetime: TimeInterval = 15

	static func cost(_ turn: CodexTurn) -> Int
	{
		turn.items.reduce(turn.id.utf8.count + 128)
		{
			total, item in
			total + 256 + [item.id,
							item.type,
							item.text,
							item.command,
							item.imagePath,
							item.cwd,
							item.output,
							item.status].compactMap
			{
				$0
			}
			.reduce(0)
			{
				$0 + $1.utf8.count
			}
			+ item.changes.reduce(0)
			{
				$0 + $1.diff.utf8.count + $1.path.utf8.count + 128
			}
			+ item.references.reduce(0)
			{
				$0 + $1.path.utf8.count + $1.name.utf8.count + 64
			}
			+ item.commandActions.reduce(0)
			{
				$0 + $1.command.utf8.count + 128
			}
		}
	}

	static func cost(_ preview: ConversationTurnSummary) -> Int
	{
		preview.turnID.utf8.count + preview.entryID.utf8.count
			+ preview.title.utf8.count + preview.reply.utf8.count + 128
	}
}

struct ConversationViewport: Equatable
{
	var turnIDs: Set<String> = []
	var anchorTurnID: String?
	var firstTurnID: String?
	var lastTurnID: String?
	var nearTop = false
	var nearBottom = false
}
