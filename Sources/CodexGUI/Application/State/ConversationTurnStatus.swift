/// Backend turn statuses share lifecycle semantics across execution and presentation.
enum ConversationTurnStatus
{
	enum Lifecycle
	{
		case running, completed, failed, interrupted, unknown
	}

	static func lifecycle(_ status: String?) -> Lifecycle
	{
		switch status
		{
		case "inProgress", "running": return .running
		case "completed": return .completed
		case "failed": return .failed
		case "interrupted", "stopped", "cancelled": return .interrupted
		default: return .unknown
		}
	}

	static func isTerminal(_ status: String?) -> Bool
	{
		switch lifecycle(status)
		{
		case .completed, .failed, .interrupted: return true
		case .running, .unknown: return false
		}
	}

	static func isRunning(_ status: String?) -> Bool
	{
		lifecycle(status) == .running
	}
}
