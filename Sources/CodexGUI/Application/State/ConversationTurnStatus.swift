/// The backend's two running-turn spellings share lifecycle and timing semantics.
enum ConversationTurnStatus
{
	static func isRunning(_ status: String?) -> Bool
	{
		status == "inProgress" || status == "running"
	}
}
