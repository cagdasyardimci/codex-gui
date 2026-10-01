import Foundation

enum AppServerEvent
{
	case turnStarted(
		threadId: String,
		turn: CodexTurn
	)
	case turnCompleted(
		threadId: String,
		turn: CodexTurn
	)
	case itemStarted(
		threadId: String,
		turnId: String,
		item: CodexItem
	)
	case itemCompleted(
		threadId: String,
		turnId: String,
		item: CodexItem
	)
	case agentMessageDelta(
		threadId: String,
		turnId: String,
		itemId: String,
		text: String
	)
	case commandOutputDelta(
		threadId: String,
		turnId: String,
		itemId: String,
		text: String
	)
	case fileChangeUpdated(
		threadId: String,
		turnId: String,
		itemId: String,
		changes: [FileChange]
	)
	case diffUpdated(
		threadId: String,
		turnId: String,
		diff: String
	)
	case planUpdated(TurnPlanUpdate)
	case tokenUsageUpdated(
		threadId: String,
		turnId: String,
		usage: ThreadTokenUsage
	)
	case threadSettingsUpdated(
		threadId: String,
		settings: ThreadSettings
	)
	case threadStatusChanged(
		threadId: String,
		status: ThreadStatus
	)
	case contextCompacted(
		threadId: String,
		turnId: String
	)
	case toolProgress(
		threadId: String,
		turnId: String,
		itemId: String,
		message: String
	)
	case interaction(PendingInteraction)
	case interactionResolved(
		threadId: String,
		requestID: String
	)
	case accountUpdated
	case skillsChanged
	case rateLimitsUpdated
	case error(
		threadId: String,
		turnId: String,
		message: String,
		willRetry: Bool
	)
}
