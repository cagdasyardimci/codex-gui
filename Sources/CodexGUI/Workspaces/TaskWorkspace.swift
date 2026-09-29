import Foundation

enum TaskWorkspacePhase: String, Codable, Sendable
{
	case preparing
	case active
	case removing
	case checkoutRemoved
	case creationCancelled
}

/// One task owns one checkout and branch. The source project may have edits, which stay there.
struct TaskWorkspace: Codable, Equatable, Identifiable, Sendable
{
	let id: UUID
	let taskID: String
	/// Filled when app-server assigns a backend conversation to this checkout.
	var threadID: String?
	let sourceProjectPath: String
	let repositoryGitDirectory: String
	let branch: String
	let checkoutPath: String
	let baseCommit: String
	let sourceWasDirty: Bool
	let createdAt: Date
	var phase: TaskWorkspacePhase

	func hasSameOwnership(as other: TaskWorkspace) -> Bool
	{
		id == other.id && taskID == other.taskID
			&& sourceProjectPath == other.sourceProjectPath
			&& repositoryGitDirectory == other.repositoryGitDirectory
			&& branch == other.branch && checkoutPath == other.checkoutPath
			&& baseCommit == other.baseCommit && sourceWasDirty == other.sourceWasDirty
			&& createdAt == other.createdAt
	}
}

enum TaskWorkspaceRecoveryKind: String, Sendable
{
	case active
	case creationInterrupted
	case removalInterrupted
	case missingCheckout
	case ownershipConflict
	case checkoutRemoved
	case creationCancelled
}

struct TaskWorkspaceRecovery: Sendable
{
	let workspace: TaskWorkspace
	let kind: TaskWorkspaceRecoveryKind
}

enum TaskWorkspaceError: LocalizedError
{
	case invalidTaskID
	case invalidThreadID
	case taskAlreadyHasWorkspace(String)
	case threadAlreadyOwned(String)
	case checkoutRootInsideSource
	case checkoutPathOccupied(String)
	case workspaceNotFound(UUID)
	case invalidPhase(TaskWorkspacePhase)
	case dirtyCheckout(String)
	case ownershipConflict(String)
	case unsafeBranchRemoval(String)
	case invalidRecord(String)
	case storageFailure(String)
	case unsupportedRecordVersion(Int)
	case gitFailure(String)

	var errorDescription: String?
	{
		switch self
		{
		case .invalidTaskID:
			"A task ID is required to own a checkout."
		case .invalidThreadID:
			"A backend conversation ID is required to bind a checkout."
		case .taskAlreadyHasWorkspace(let taskID):
			"Task \(taskID) already has a workspace record."
		case .threadAlreadyOwned(let threadID):
			"Backend conversation \(threadID) is already bound to a task workspace."
		case .checkoutRootInsideSource:
			"The checkout directory must be outside Git worktrees and repository metadata."
		case .checkoutPathOccupied(let path):
			"The checkout path is already occupied: \(path)."
		case .workspaceNotFound(let id):
			"No workspace record exists for \(id)."
		case .invalidPhase(let phase):
			"The checkout operation is not available while the workspace is \(phase.rawValue)."
		case .dirtyCheckout(let path):
			"The checkout contains changes or files and was left in place: \(path)."
		case .ownershipConflict(let detail):
			"Checkout ownership could not be verified: \(detail). No files were removed."
		case .unsafeBranchRemoval(let branch):
			"Branch \(branch) changed or is checked out elsewhere. It was left in place."
		case .invalidRecord(let detail):
			"The workspace record is invalid: \(detail). It was left unchanged."
		case .storageFailure(let detail):
			"Workspace records could not be locked: \(detail). No checkout operation was started."
		case .unsupportedRecordVersion(let version):
			"Workspace record version \(version) is unsupported. It was left unchanged."
		case .gitFailure(let detail):
			"Git worktree operation failed: \(detail)"
		}
	}
}
