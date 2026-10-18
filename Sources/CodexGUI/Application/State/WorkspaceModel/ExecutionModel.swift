import Foundation

enum AgentTurnOutcome: Equatable
{
	case completed
	case stopped
	case failed(String)
}

struct ExecutionOwner: Equatable
{
	/// Remains valid when thread/turn IDs are absent or assigned later.
	var submission: OperationContext
}

struct ExecutionModel
{
	var gitTurnBaselineRevisions: [String: Int] = [:]
	var gitTurnBaselineBindings: [String: GitTurnBaselineBindingStatus] = [:]
	var pendingGitTurnBaselineCapture: PendingGitTurnBaselineCapture?
	var owner: ExecutionOwner?
	var activeThreadID: String?
	var activeTurnID: String?
	var statusMessage: String?
	var deferredTurnOutcome: ExecutionState?
	var deferredTurnMessage: String?
	var submissionRequest: OperationContext?
	var state: ExecutionState = .disconnected
	var agentOutcome: AgentTurnOutcome?
	var commandLifetime = TaskCommandLifetime()
	var commandEventRevisions: [String: Int] = [:]
	var pendingInteractions: [PendingInteraction] = []
	/// A possibly sent response remains reserved until server resolution or disconnection.
	var pendingResponses: [String: InteractionResponseOperation] = [:]
	var pendingSteering: OperationContext?
	var pendingInterruption: InterruptionOperation?
	var lastReconciledRequestID: UUID?
	var pendingReconciliation: ReconciliationOperation?
	var activePlan: TurnPlanUpdate?
	var activeActivity: String?
	var outcomeMessage: String?

	/// Stop intent and interrupt transport acknowledgement are independent facts.
	var stopRequested = false
	var stopContext: OperationContext?
	var interruptRequestSent = false
	/// A disconnected transport does not establish the outcome of a remote request.
	var needsReconciliation = false
	var hasUncertainRequest = false
	var reconcilingCommandOutcome = false

	/// Terminal agent evidence never clears the independent command barrier.
	var isTaskActive: Bool
	{
		state.isBusy || commandLifetime.hasPendingCommands || hasUncertainRequest
			|| (needsReconciliation && activeThreadID != nil)
	}

	var blocksCleanup: Bool
	{
		isTaskActive || needsReconciliation
	}
}
