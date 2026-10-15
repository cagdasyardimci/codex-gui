import Foundation

/// Logical payload estimates exclude AppKit overhead and do not measure process allocations.
/// Canonical source values copied into transcript entries are accounted for once.
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

	static func sum(_ costs: Int...) -> Int
	{
		costs.reduce(0)
		{
			let result = $0.addingReportingOverflow($1)
			return result.overflow ? Int.max : result.partialValue
		}
	}

	static func textCost(_ values: String?...) -> Int
	{
		values.reduce(0)
		{
			sum(
				$0,
				$1?.utf8.count ?? 0
			)
		}
	}

	static func cost(_ turn: CodexTurn) -> Int
	{
		turn.items.reduce(sum(
			128,
			textCost(
				turn.id,
				turn.status,
				turn.error
			)
		))
		{
			sum(
				$0,
				cost($1)
			)
		}
	}

	static func cost(_ item: CodexItem) -> Int
	{
		sum(
			256,
			textCost(
				item.id,
				item.type,
				item.text,
				item.command,
				item.imagePath,
				item.cwd,
				item.output,
				item.status
			),
			item.changes.reduce(0)
			{
				sum(
					$0,
					cost($1)
				)
			},
			item.references.reduce(0)
			{
				sum(
					$0,
					cost($1)
				)
			},
			item.commandActions.reduce(0)
			{
				sum(
					$0,
					cost($1)
				)
			},
			item.sourceActivity.map(cost) ?? 0,
			item.subagentActivity.map(cost) ?? 0
		)
	}

	static func cost(_ source: ConversationSourceActivity) -> Int
	{
		sum(
			128,
			textCost(
				source.id,
				source.provider,
				source.operation,
				source.summary,
				source.detail,
				source.status,
				source.displayPayload,
				source.displayLanguage
			),
			source.page.map
			{
				textCost(
					$0.id,
					$0.title,
					$0.url
				) + 64
			} ?? 0
		)
	}

	static func cost(_ activity: CodexSubagentActivity) -> Int
	{
		sum(
			64,
			textCost(
				activity.kind,
				activity.threadID,
				activity.path
			)
		)
	}

	static func cost(_ change: FileChange) -> Int
	{
		sum(
			128,
			textCost(
				change.path,
				change.kind,
				change.movePath,
				change.diff
			)
		)
	}

	static func cost(_ reference: UserMessageReference) -> Int
	{
		sum(
			64,
			textCost(
				reference.id,
				reference.name,
				reference.path
			)
		)
	}

	static func cost(_ action: CodexCommandAction) -> Int
	{
		sum(
			128,
			textCost(
				action.command,
				action.name,
				action.path,
				action.query
			)
		)
	}

	static func cost(_ preview: ConversationTurnPreview) -> Int
	{
		sum(
			128,
			textCost(
				preview.turnID,
				preview.entryID,
				preview.title,
				preview.reply,
				preview.replySource
			)
		)
	}
}
