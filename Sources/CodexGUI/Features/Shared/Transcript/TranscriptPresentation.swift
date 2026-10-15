import Foundation

/// Render inputs shared by the full conversation and a child agent's history.
struct TranscriptPresentation: Equatable
{
	struct Navigation: Equatable
	{
		let turnReferences: [ConversationTurnReference]
		let turnPreviews: [ConversationTurnPreview]
		let turnPreviewErrors: [String: String]
		let canLoadEarlierTurnReferences: Bool
		let bookmarks: [ConversationBookmark]
	}

	let owner: FeaturePresentationOwner
	let entries: [ConversationEntry]
	let turnTimings: [ConversationTurnTiming]
	let canLoadEarlierTurns: Bool
	let navigation: Navigation?
	let executionState: ExecutionState
	let activeThreadID: String?
	let activeTurnID: String?
	var interactionRevision = 0

	var selectedThreadID: String?
	{
		owner.selectedThreadID
	}
}
