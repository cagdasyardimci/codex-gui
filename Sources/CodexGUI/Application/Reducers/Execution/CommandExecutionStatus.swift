/// Only explicit command exit evidence clears a pending command's ownership barrier.
enum CommandExecutionStatus
{
	static func isTerminal(_ status: String?) -> Bool
	{
		switch status
		{
		case "completed", "failed", "declined", "interrupted", "cancelled": return true
		default: return false
		}
	}
}
