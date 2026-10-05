import Foundation

/// A terminal agent turn does not establish that an approved command has exited.
struct TaskCommandOwnership: Codable, Hashable
{
	let threadID: String
	let turnID: String
	let itemID: String
}

struct TaskCommandLifetime
{
	private(set) var pending: Set<TaskCommandOwnership> = []

	init(pending: [TaskCommandOwnership] = [])
	{
		self.pending = Set(pending)
	}

	var hasPendingCommands: Bool
	{
		!pending.isEmpty
	}

	func owns(
		threadID: String,
		turnID: String,
		itemID: String? = nil
	) -> Bool
	{
		pending.contains
		{
			$0.threadID == threadID && $0.turnID == turnID
				&& (itemID == nil || $0.itemID == itemID)
		}
	}

	mutating func observe(
		_ item: CodexItem,
		threadID: String,
		turnID: String
	)
	{
		guard item.type == "commandExecution"
		else
		{
			return
		}
		let owner = TaskCommandOwnership(
			threadID: threadID,
			turnID: turnID,
			itemID: item.id
		)
		if CommandExecutionStatus.isTerminal(item.status)
		{
			pending.remove(owner)
		}
		else
		{
			pending.insert(owner)
		}
	}

	/// Missing items retain their barrier; only explicit terminal item evidence clears it.
	mutating func reconcile(
		threadID: String,
		turns: [CodexTurn]
	)
	{
		for turn in turns
		{
			for item in turn.items
			{
				observe(
					item,
					threadID: threadID,
					turnID: turn.id
				)
			}
		}
	}
}
