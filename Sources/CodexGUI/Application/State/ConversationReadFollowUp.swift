import Foundation

/// Captured value scope for a follow-up whose request identity is assigned by inputs.
struct ConversationReadScope: Equatable
{
	let workspace: WorkspaceIdentity
	let generation: Int
	let threadID: String
}

enum ConversationReadFollowUp: Equatable
{
	case references(
		ConversationReadScope,
		cursor: String?
	)
	case window(
		ConversationReadScope,
		reference: ConversationTurnReference,
		commandRevision: Int
	)
	case previewExpiry(ConversationReadScope)

	var scope: ConversationReadScope
	{
		switch self
		{
		case .references(
			let scope,
			_
		), .window(
			let scope,
			_,
			_
		), .previewExpiry(let scope):
			return scope
		}
	}
}
