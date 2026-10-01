import Foundation

/// A presentation request retains the exact draft and workspace that proposed the command.
struct SlashCommandPresentationRequest
{
	let context: OperationContext
	let invocation: SlashCommandInvocation
	let conversation: ConversationKey
	let draft: ComposerDraft
	var id: UUID
	{
		context.requestID
	}
}

enum ForkRecoveryChoice
{
	case resume(threadID: String)
	case continueOriginal
}

struct ComposerCommandModel
{
	var error: String?
	var pendingFork: SlashCommandPresentationRequest?
	var uncertainFork: OperationContext?
	var forkRecoveryPresentation: SlashCommandPresentationRequest?
	var forkRecoveryListReady = false
	var settingsIntroducedReconciliation = false
	var tokenUsage: [String: ThreadTokenUsage] = [:]
	var threadStatuses: [String: ThreadStatus] = [:]
	var threadSettings: [String: ThreadSettings] = [:]
	var pendingTurn: ComposerCommandTurnOperation?
	var pendingSettings: ComposerCommandSettingsOperation?
	var planModes: [ConversationKey: CollaborationModeKind] = [:]

	var blocksNewWork: Bool
	{
		pendingFork != nil || uncertainFork != nil || pendingTurn != nil || pendingSettings != nil
	}
}

struct ComposerCommandTurnOperation
{
	enum Kind
	{
		case compact
		case review(ReviewTarget)
	}
	let request: SlashCommandPresentationRequest
	let kind: Kind
	let previousTurnIDs: Set<String>
	var transportFinished = false
	var terminalObserved = false
}

struct ComposerCommandSettingsOperation
{
	let request: SlashCommandPresentationRequest
	let mode: CollaborationMode
	var outcomeUncertain = false
	var transportFinished = false
	var observedSettings = false
	var retryingUnknownMode = false
}

enum ComposerCommandAction
{
	case requested(SlashCommandPresentationRequest)
	case acknowledged(SlashCommandPresentationRequest)
	case rejected(
		OperationContext,
		String
	)
	case forkRecoveryRequested(
		SlashCommandPresentationRequest,
		ForkRecoveryChoice
	)
	case forkFinished(
		SlashCommandPresentationRequest,
		OperationResult<ThreadDetail>
	)
	case compactAcknowledged(
		ComposerCommandTurnOperation,
		OperationResult<Void>
	)
	case reviewAcknowledged(
		ComposerCommandTurnOperation,
		OperationResult<ReviewStartResult>
	)
	case settingsFinished(
		ComposerCommandSettingsOperation,
		OperationResult<Void>
	)
	case settingsRetryRequested(ComposerCommandSettingsOperation)
	case backendObserved(
		OperationContext,
		AppServerEvent
	)
}
