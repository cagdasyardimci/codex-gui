import Foundation

/// Indexed entry mutations update byte totals without rescanning a streaming transcript.
struct ConversationEntryPayloadCosts
{
	struct EntryCost
	{
		let id: String
		let turnID: String
		let textBytes: Int
		let additionalBytes: Int
	}

	private(set) var textBytes = 0
	private(set) var textByTurn: [String: Int] = [:]
	private(set) var additionalByEntry: [String: Int] = [:]
	private(set) var additionalRevision = 0

	init(entries: [ConversationEntry])
	{
		for entry in entries
		{
			append(entry)
		}
	}

	static func turnID(for entryID: String) -> String
	{
		String(entryID.prefix
		{
			$0 != ":"
		})
	}

	static func cost(_ entry: ConversationEntry) -> EntryCost
	{
		var references = Set<String>()
		let referenceBytes = (entry.imageAttachments + entry.sourceReferences).reduce(0)
		{
			total, reference in
			guard references.insert(reference.id).inserted
			else
			{
				return total
			}
			return ConversationCachePolicy.sum(
				total,
				ConversationCachePolicy.cost(reference)
			)
		}
		let activityBytes: Int
		switch entry.activity
		{
		case .command(let command):
			activityBytes = ConversationCachePolicy.sum(
				128,
				ConversationCachePolicy.textCost(
					command.command,
					command.cwd,
					command.output,
					command.status
				),
				command.actions.reduce(0)
				{
					ConversationCachePolicy.sum(
						$0,
						ConversationCachePolicy.cost($1)
					)
				}
			)
		case .image(let path): activityBytes = path.utf8.count
		case .subagent(let activity): activityBytes = ConversationCachePolicy.cost(activity)
		case .fileChanges(
			let changes,
			let status
		):
			activityBytes = changes.reduce(status.utf8.count)
			{
				ConversationCachePolicy.sum(
					$0,
					ConversationCachePolicy.cost($1)
				)
			}
		case nil: activityBytes = 0
		}
		return EntryCost(
			id: entry.id,
			turnID: turnID(for: entry.id),
			textBytes: ConversationCachePolicy.sum(
				64,
				ConversationCachePolicy.textCost(
					entry.id,
					entry.title,
					entry.body
				)
			),
			additionalBytes: ConversationCachePolicy.sum(
				referenceBytes,
				activityBytes,
				entry.sourceActivity
					.map(ConversationCachePolicy.cost) ?? 0
			)
		)
	}

	mutating func append(_ entry: ConversationEntry)
	{
		let cost = Self.cost(entry)
		textBytes = ConversationCachePolicy.sum(
			textBytes,
			cost.textBytes
		)
		textByTurn[cost.turnID, default: 0] = ConversationCachePolicy.sum(
			textByTurn[cost.turnID, default: 0],
			cost.textBytes
		)
		if cost.additionalBytes > 0
		{
			additionalByEntry[cost.id, default: 0] = ConversationCachePolicy.sum(
				additionalByEntry[cost.id, default: 0],
				cost.additionalBytes
			)
			additionalRevision += 1
		}
	}

	mutating func replace(
		_ previous: EntryCost,
		with entry: ConversationEntry
	)
	{
		let next = Self.cost(entry)
		textBytes = ConversationCachePolicy.sum(
			max(
				0,
				textBytes - previous.textBytes
			),
			next.textBytes
		)
		let retainedText = max(
			0,
			textByTurn[previous.turnID, default: 0] - previous.textBytes
		)
		textByTurn[previous.turnID] = retainedText == 0 ? nil : retainedText
		textByTurn[next.turnID, default: 0] = ConversationCachePolicy.sum(
			textByTurn[next.turnID, default: 0],
			next.textBytes
		)
		if previous.id != next.id || previous.additionalBytes != next.additionalBytes
		{
			let retained = max(
				0,
				additionalByEntry[previous.id, default: 0] - previous
					.additionalBytes
			)
			additionalByEntry[previous.id] = retained == 0 ? nil : retained
			if next.additionalBytes > 0
			{
				additionalByEntry[next.id, default: 0] = ConversationCachePolicy.sum(
					additionalByEntry[next.id, default: 0],
					next.additionalBytes
				)
			}
			additionalRevision += 1
		}
	}
}
