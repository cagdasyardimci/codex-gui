import Foundation

/// Only explicit cross-client ownership errors put a conversation in read-only mode.
enum ConversationLock
{
	static func isAnotherApp(_ message: String) -> Bool
	{
		let value = message.lowercased()
		if value.contains("already has an active writer")
		{
			return true
		}
		let namesAnotherOwner = ["another app",
									"another application",
									"another client",
									"another instance",
									"another process"].contains
		{
			value.contains($0)
		}
		return namesAnotherOwner && ["open", "active", "in use", "owned", "locked"].contains
		{
			value.contains($0)
		}
	}
}
