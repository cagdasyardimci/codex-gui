import Foundation

/// Provenance survives restart without transferring the old session's execution authority.
struct GitTurnBaselineIdentity: Equatable, Codable, Sendable
{
	let id: UUID
	let workspaceSessionID: UUID
	let repositoryRoot: String
	let executionGeneration: Int
	let submissionRequestID: UUID
	let threadID: String
	/// Captured owner spelling after the effect validates its physical repository root.
	var workspaceCheckoutPath: String? = nil

	var workspace: WorkspaceIdentity
	{
		WorkspaceIdentity(
			sessionID: workspaceSessionID,
			canonicalCheckoutPath: workspaceCheckoutPath ?? repositoryRoot
		)
	}
}

struct GitTurnBaselineReference: Equatable, Codable, Sendable
{
	let identity: GitTurnBaselineIdentity
	let capturedAt: Date
	let trackedFileCount: Int
	let byteCount: Int
	let acceptedTurnID: String?

	func bound(to turnID: String) -> GitTurnBaselineReference
	{
		GitTurnBaselineReference(
			identity: identity,
			capturedAt: capturedAt,
			trackedFileCount: trackedFileCount,
			byteCount: byteCount,
			acceptedTurnID: turnID
		)
	}
}

struct GitTurnBaselineCaptureRequest: Equatable, Sendable
{
	let context: OperationContext
	let threadID: String
	let repositoryRoot: String
}

enum GitTurnBaselineResult: Equatable, Sendable
{
	case captured(GitTurnBaselineReference)
	case unavailable(GitComparisonFailure)
}

struct GitTurnBaselineLimits: Equatable, Sendable
{
	var maximumPaths = 10_000
	var maximumFileBytes = 8 * 1024 * 1024
	var maximumCaptureBytes = 64 * 1024 * 1024
	var maximumPatchBytes = 8 * 1024 * 1024
	var maximumBaselines = 8
	var maximumRetainedBytes = 512 * 1024 * 1024
}
