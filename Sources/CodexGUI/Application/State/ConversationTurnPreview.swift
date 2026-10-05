import Foundation

/// Compact text retained independently of transcript rendering and loaded turn bodies.
struct ConversationTurnPreview: Equatable, Sendable
{
	let turnID: String
	let entryID: String
	let title: String
	let reply: String
}
