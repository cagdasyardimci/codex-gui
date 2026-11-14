import Foundation

/// Navigation identity for an accepted first message before Codex assigns a thread ID.
struct PendingChatPresentation: Equatable
{
	let requestID: UUID
	let projectPath: String
	let title: String
	let isSelected: Bool
}
