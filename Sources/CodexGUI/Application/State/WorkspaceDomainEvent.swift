import Foundation

/// Accepted feature transitions compose atomically before effects and publication.
enum WorkspaceDomainEvent
{
	case connectionBegan
	case connectionDisconnected
	case projectRestored
	case completedHistoryRefreshed
	case conversationListAccepted(ConversationListOperation)
	case submissionAccepted(ComposerSubmission)
	case submissionPrepared(PreparedSubmission)
	case backendObserved(AppServerEvent)
	case historyAccepted(
		ThreadDetail,
		threadID: String
	)
	case completedHistoryReadRequested(ConversationReadOperation)
	case conversationHistoryFinished(
		NavigationHistoryRead,
		OperationResult<Bool>
	)
	case conversationContentChanged
	case conversationSelectionChanged(String?)
}

struct WorkspaceReduction
{
	var effects: [WorkspaceEffect] = []
	var domainEvents: [WorkspaceDomainEvent] = []
	var presentationCommands: [WorkspacePresentationCommand] = []
}
