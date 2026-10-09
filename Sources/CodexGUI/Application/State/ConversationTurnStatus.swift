/// Backend turn statuses share lifecycle and presentation semantics.
enum ConversationTurnStatus
{
	static func isTerminal(_ status: String?) -> Bool
	{
		guard let status
		else
		{
			return false
		}
		return ["completed", "failed", "interrupted", "stopped", "cancelled"].contains(status)
	}

	static func isRunning(_ status: String?) -> Bool
	{
		status == "inProgress" || status == "running"
	}
}
