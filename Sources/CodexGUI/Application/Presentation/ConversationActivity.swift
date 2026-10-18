import Foundation

struct ConversationCommand: Equatable
{
	let command: String
	let cwd: String?
	var output: String
	let status: String
	let exitCode: Int?
	let durationMs: Double?
	let actions: [CodexCommandAction]

	static func == (left: Self, right: Self) -> Bool
	{
		left.command.utf8.elementsEqual(right.command.utf8) && left.cwd == right.cwd
			&& left.output.utf8.elementsEqual(right.output.utf8) && left.status == right.status
			&& left.exitCode == right.exitCode && left.durationMs == right.durationMs
			&& left.actions == right.actions
	}
}

enum ConversationActivity: Equatable
{
	case command(ConversationCommand)
	case image(path: String)
	case subagent(CodexSubagentActivity)
	case fileChanges(
		[FileChange],
		status: String
	)

	static func == (left: Self, right: Self) -> Bool
	{
		switch (left, right)
		{
		case (.command(let left), .command(let right)): return left == right
		case (.image(let left), .image(let right)): return left == right
		case (.subagent(let left), .subagent(let right)): return left == right
		case (.fileChanges(
			let left,
			let leftStatus
		), .fileChanges(
			let right,
			let rightStatus
		)):
			return leftStatus == rightStatus && FileChange.haveSameExactContent(
				left,
				right
			)
		default: return false
		}
	}
}

struct ConversationTurnTiming: Equatable
{
	let turnID: String
	let status: String
	let startedAt: Date?
	let completedAt: Date?
	let durationMs: Double?

	init(
		turnID: String,
		status: String,
		startedAt: Date? = nil,
		completedAt: Date? = nil,
		durationMs: Double? = nil
	)
	{
		self.turnID = turnID
		self.status = status
		self.startedAt = startedAt
		self.completedAt = completedAt
		self.durationMs = durationMs
	}

	init(
		turn: CodexTurn,
		previous: ConversationTurnTiming? = nil,
		observedAt: Date? = nil
	)
	{
		turnID = turn.id
		status = turn.status
		let isRunning = ConversationTurnStatus.isRunning(turn.status)
		// Only live observations supply a local fallback; history must not invent elapsed time.
		startedAt = turn.startedAt ?? previous?.startedAt
			?? (isRunning ? observedAt : nil)
		completedAt = turn.completedAt ?? previous?.completedAt
			?? (!isRunning && startedAt != nil ? observedAt : nil)
		durationMs = turn.durationMs ?? previous?.durationMs
	}
}

extension Optional where Wrapped == ConversationActivity
{
	var isFileChange: Bool
	{
		if case .fileChanges = self
		{
			return true
		}
		return false
	}
}
