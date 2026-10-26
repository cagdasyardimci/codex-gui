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
	case threadNameUpdated(
		threadId: String,
		name: String?
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
	case remoteControlStatusChanged(RemoteControlStatus)
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

extension AppServerEvent
{
	var turnContentIdentity: (threadID: String, turnID: String)?
	{
		switch self
		{
		case .turnStarted(
			let threadID,
			let turn
		), .turnCompleted(
			let threadID,
			let turn
		):
			return (threadID, turn.id)
		case .itemStarted(
			let threadID,
			let turnID,
			_
		), .itemCompleted(
			let threadID,
			let turnID,
			_
		),
		.agentMessageDelta(
			let threadID,
			let turnID,
			_,
			_
		),
		.commandOutputDelta(
			let threadID,
			let turnID,
			_,
			_
		),
		.fileChangeUpdated(
			let threadID,
			let turnID,
			_,
			_
		), .diffUpdated(
			let threadID,
			let turnID,
			_
		):
			return (threadID, turnID)
		default: return nil
		}
	}
}
