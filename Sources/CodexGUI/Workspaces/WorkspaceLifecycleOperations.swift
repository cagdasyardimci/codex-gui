import Foundation

/// A new runtime session cannot inherit the previous session's cleanup or quit authority.
enum WorkspaceLifecycleOwner: Hashable
{
	case source(sessionID: UUID)
	case managed(
		workspaceID: UUID,
		sessionID: UUID
	)

	var sessionID: UUID
	{
		switch self
		{
		case .source(let id), .managed(
			_,
			let id
		): id
		}
	}
}

struct WorkspaceLifecycleOwnerReference: Equatable, Hashable
{
	let owner: WorkspaceLifecycleOwner
	let workspace: WorkspaceIdentity
}

struct WorkspaceLifecycleObservation: Equatable
{
	let reference: WorkspaceLifecycleOwnerReference
	var executionState: ExecutionState = .disconnected
	var activeThreadID: String?
	var unresolvedCommands = false
	var remoteOutcomeUncertain = false
	var needsReconciliation = false
	var composerOutcomeUncertain = false
	var pendingLocalWrites = false
	var managementInProgress = false
	var cleanupReservation: UUID?

	var requiresRemoteStop: Bool
	{
		executionState.isBusy || unresolvedCommands || remoteOutcomeUncertain
			|| (needsReconciliation && activeThreadID != nil)
	}

	var refusesOrdinaryExit: Bool
	{
		remoteOutcomeUncertain || composerOutcomeUncertain
	}

	var blocksCleanup: Bool
	{
		requiresRemoteStop || needsReconciliation || composerOutcomeUncertain
			|| managementInProgress
	}
}

struct WorkspaceCreationRequest: Equatable
{
	let requestID: UUID
	let source: WorkspaceIdentity
	let selectionEpoch: Int
	let taskID: String
	let name: String
	let ownerSessionID: UUID
}

struct WorkspaceSelectionRequest: Equatable
{
	let requestID: UUID
	let ownerSessionID: UUID
	let selectionEpoch: Int
	let expected: TaskWorkspace
}

struct WorkspaceCleanupRequest: Equatable
{
	let requestID: UUID
	let owner: WorkspaceLifecycleOwnerReference?
	let expected: TaskWorkspace
}

struct WorkspaceRecoveryRequest: Equatable
{
	let requestID: UUID
	let recordsRevision: Int
	var cleanup: WorkspaceCleanupRequest? = nil
}

enum WorkspaceQuitPurpose: Equatable
{
	case termination, stopAll
}
struct WorkspaceQuitRequest: Equatable
{
	let requestID: UUID
	var purpose: WorkspaceQuitPurpose = .termination
}

/// Every operation captures the durable record or source identity at its input boundary.
enum WorkspaceLifecycleGitEffect
{
	case recover(WorkspaceRecoveryRequest)
	case create(WorkspaceCreationRequest)
	case verifySelection(WorkspaceSelectionRequest)
	case remove(WorkspaceCleanupRequest)
	case cancelCreation(
		requestID: UUID,
		expected: TaskWorkspace
	)
}

enum WorkspaceCoordinatorEffect
{
	case git(WorkspaceLifecycleGitEffect)
	case attachVerifiedOwner(
		WorkspaceSelectionRequest,
		TaskWorkspace
	)
	case reserveCleanup(WorkspaceCleanupRequest)
	case drainCleanup(WorkspaceCleanupRequest)
	case releaseCleanup(WorkspaceCleanupRequest)
	case managedRecordRecoveryConflicted(
		WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		cleanup: WorkspaceCleanupRequest?,
		message: String
	)
	case managedRecordRecovered(
		WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		recovered: TaskWorkspace
	)
	case removeOwner(WorkspaceLifecycleOwnerReference)
	case cancelRequest(UUID)
	case confirmQuit(WorkspaceQuitRequest)
	case stopOwners(
		WorkspaceQuitRequest,
		[WorkspaceLifecycleOwnerReference]
	)
	case freezeWritesAndDrainQuit(
		WorkspaceQuitRequest,
		Set<WorkspaceLifecycleOwnerReference>
	)
	case completeQuit(
		WorkspaceQuitRequest,
		approved: Bool
	)
	case notifyQuitCompletion(
		WorkspaceQuitRequest,
		approved: Bool
	)
	case ownerTransition(
		previous: WorkspaceLifecycleObservation?,
		current: WorkspaceLifecycleObservation
	)
}
