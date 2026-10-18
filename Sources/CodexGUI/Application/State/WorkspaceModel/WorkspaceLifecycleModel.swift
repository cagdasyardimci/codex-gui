import Foundation

struct WorkspaceQuitReservation: Equatable
{
	let requestID: UUID
	let reference: WorkspaceLifecycleOwnerReference
}

struct WorkspaceLifecycleModel
{
	var owner: WorkspaceLifecycleOwner?
	var managedWorkspace: TaskWorkspace?
	var managedOwnershipConflict: String?
	var lastCleanupRequestID: UUID?
	var cleanupReservation: WorkspaceCleanupRequest?
	var quitReservation: WorkspaceQuitReservation?
	var isShutdown = false
	var statusMessage: String?
	var backendDiagnostics: BackendDiagnosticsSnapshot?
	var validatedReusableReferences: [ConversationKey: [ComposerContextItem]] = [:]
	var validatedImagePaths: Set<String> = []
	var referenceValidationCandidates: [ConversationKey: [ComposerContextItem]] = [:]
	var pendingSourceStartup: OperationContext?
	var pendingProjectOpening: OperationContext?
	var pendingArchivedSelection: OperationContext?
	var pendingInputPreparation: ComposerInputPreparationOperation?
	var recoveryListRequestID: UUID?
	var bootstrapRequestID: UUID?
	var persistenceFailures: [String: WorkspaceLifecyclePersistenceFailure] = [:]
	var successfulWriteRevisions: [String: Int] = [:]
}

struct WorkspaceLifecyclePersistenceFailure
{
	let revision: Int
	let message: String
}
