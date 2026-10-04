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
}

enum ConversationActivity: Equatable
{
	case command(ConversationCommand)
	case image(path: String)
	case fileChanges(
		[FileChange],
		status: String
	)
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
		// Only live observations supply a local fallback; history must not invent elapsed time.
		startedAt = turn.startedAt ?? previous?.startedAt
			?? (turn.status == "inProgress" ? observedAt : nil)
		completedAt = turn.completedAt ?? previous?.completedAt
			?? (turn.status != "inProgress" && startedAt != nil ? observedAt : nil)
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
