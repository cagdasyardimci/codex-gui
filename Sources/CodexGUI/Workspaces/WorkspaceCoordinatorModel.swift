import Foundation

struct WorkspaceCleanupTransition
{
	enum Stage: Equatable
	{
		case reserving, draining, removing, recovering
	}
	let request: WorkspaceCleanupRequest
	var stage: Stage
}

enum WorkspaceQuitTransition
{
	case idle
	case terminating(
		WorkspaceQuitRequest,
		Set<WorkspaceLifecycleOwnerReference>
	)
	case confirming(WorkspaceQuitRequest)
	case stopping(WorkspaceQuitRequest)
	case draining(
		WorkspaceQuitRequest,
		Set<WorkspaceLifecycleOwnerReference>
	)
}

/// Runtime stores, observer tokens, Tasks and effect dependencies stay outside this value.
struct WorkspaceCoordinatorModel
{
	var source: WorkspaceIdentity
	var selectedOwner: WorkspaceLifecycleOwner
	var selectionEpoch = 0
	var recordsRevision = 0
	var workspaces: [UUID: TaskWorkspace] = [:]
	var recoveryIssues: [UUID: TaskWorkspaceRecoveryKind] = [:]
	var owners: [WorkspaceLifecycleOwner: WorkspaceLifecycleObservation] = [:]
	var registeredOwners: [WorkspaceLifecycleOwner: WorkspaceIdentity] = [:]
	var pendingSelection: WorkspaceSelectionRequest?
	var pendingCreations: [UUID: WorkspaceCreationRequest] = [:]
	var pendingCleanup: [UUID: WorkspaceCleanupTransition] = [:]
	var pendingRecovery: WorkspaceRecoveryRequest?
	var pendingCancellation: [UUID: TaskWorkspace] = [:]
	var quit: WorkspaceQuitTransition = .idle
	var pendingQuitCompletion: WorkspaceQuitCompletion?
	var message: String?

	init(source: WorkspaceIdentity)
	{
		self.source = source
		selectedOwner = .source(sessionID: source.sessionID)
		registeredOwners[selectedOwner] = source
	}

	var acceptsNewWork: Bool
	{
		switch quit
		{
		case .idle, .confirming:
			true
		case .stopping, .draining, .terminating:
			false
		}
	}

	var hasRemoteOwners: Bool
	{
		owners.values.contains(where: \.requiresRemoteStop)
	}

	var hasUncertainOwners: Bool
	{
		owners.values.contains(where: \.refusesOrdinaryExit)
			|| registeredOwners.contains
			{
				owners[$0.key]?.reference.workspace != $0.value
			}
	}
}

struct WorkspaceQuitCompletion
{
	let request: WorkspaceQuitRequest
	let approved: Bool
	let owners: Set<WorkspaceLifecycleOwnerReference>
}

enum WorkspaceCoordinatorAction
{
	case sourceOpened(WorkspaceIdentity)
	case sourceSelected
	case ownerObserved(WorkspaceLifecycleObservation)
	case ownerRemoved(WorkspaceLifecycleOwnerReference)
	case bindingObserved(
		WorkspaceLifecycleOwnerReference,
		TaskWorkspace
	)
	case creationRequested(WorkspaceCreationRequest)
	case creationFinished(
		WorkspaceCreationRequest,
		OperationResult<TaskWorkspace>
	)
	case selectionRequested(WorkspaceSelectionRequest)
	case selectionVerified(
		WorkspaceSelectionRequest,
		OperationResult<TaskWorkspace>
	)
	case recoveryRequested(WorkspaceRecoveryRequest)
	case recoveryFinished(
		WorkspaceRecoveryRequest,
		OperationResult<[TaskWorkspaceRecovery]>
	)
	case cleanupRequested(WorkspaceCleanupRequest)
	case cleanupReserved(
		WorkspaceCleanupRequest,
		accepted: Bool
	)
	case cleanupPersistenceDrained(
		WorkspaceCleanupRequest,
		OperationResult<Void>
	)
	case cleanupFinished(
		WorkspaceCleanupRequest,
		OperationResult<TaskWorkspace>
	)
	case cancellationRequested(
		requestID: UUID,
		expected: TaskWorkspace
	)
	case cancellationFinished(
		requestID: UUID,
		expected: TaskWorkspace,
		OperationResult<TaskWorkspace>
	)
	case quitRequested(WorkspaceQuitRequest)
	case quitConfirmationFinished(
		WorkspaceQuitRequest,
		approved: Bool
	)
	case quitReservationFailed(
		WorkspaceQuitRequest,
		OperationFailure
	)
	case quitCompletionRequested(
		WorkspaceQuitRequest,
		approved: Bool,
		frozenOwners: Set<WorkspaceLifecycleOwnerReference>
	)
	case quitPersistenceDrained(
		WorkspaceQuitRequest,
		OperationResult<Void>
	)
}
