import Foundation

enum GitComparisonScope: String, CaseIterable, Equatable, Sendable
{
	case lastTurn = "Last Turn"
	case uncommitted = "Uncommitted"
	case unstaged = "Unstaged"
	case staged = "Staged"
	case committed = "Committed"
	case branch = "Branch"

	var title: String
	{
		rawValue
	}
}

/// Captures the owning runtime and conversation before starting the request.
struct GitComparisonRequest: Equatable, Sendable
{
	let owner: FeaturePresentationOwner
	let repositoryRoot: String
	let scope: GitComparisonScope
	let generation: Int
	var baseRevision: String? = nil
	var targetRevision: String? = nil
	var lastTurnBaseline: GitTurnBaselineReference? = nil
	var lastTurnID: String? = nil
	var reportedChanges: [FileChange]? = nil
}

enum GitComparisonFailure: Error, Equatable, Sendable
{
	case repositoryUnavailable
	case notGitRepository
	case invalidRevision(String)
	case lastTurnUnavailable
	case reportedChangesIncomplete
	case lastTurnBaselineUnavailable(String)
	case baselineOwnershipMismatch
	case oversized
	case unsupportedTextEncoding
	case repositoryChanged
	case cancelled
	case unmergedIndex
	case failed(String)

	var message: String
	{
		switch self
		{
		case .repositoryUnavailable: return "The repository is unavailable."
		case .notGitRepository: return "This workspace is not a Git repository."
		case .invalidRevision(let revision): return "Revision unavailable: \(revision)"
		case .lastTurnBaselineUnavailable(let reason): return "Last Turn unavailable: " + reason
		case .baselineOwnershipMismatch: return "This baseline belongs to another chat or turn."
		case .lastTurnUnavailable:
			return "Last Turn unavailable: this task has no available file-change reports "
				+ "for the selected turn."
		case .reportedChangesIncomplete:
			return "Last Turn unavailable: reported edits cannot be combined into reliable net "
				+ "changes. Individual edits remain in the conversation."
		case .oversized: return "The comparison exceeds the 8 MiB preview limit."
		case .unsupportedTextEncoding: return "This comparison contains non-UTF-8 text."
		case .repositoryChanged:
			return "The repository changed during comparison. Refresh to retry."
		case .cancelled: return "The comparison was cancelled."
		case .unmergedIndex: return "Resolve index conflicts before reading this comparison."
		case .failed(let message): return message
		}
	}
}

enum GitComparisonResult: Equatable, Sendable
{
	case snapshot(GitComparisonSnapshot)
	case unavailable(GitComparisonFailure)
}

enum GitComparisonChangeKind: String, Equatable, Sendable
{
	case modified, added, deleted, renamed, copied
}

struct GitComparisonHunk: Equatable, Sendable
{
	let header: String
	let text: String
	let oldStart: Int
	let newStart: Int
}

struct GitComparisonFile: Identifiable, Equatable, Sendable
{
	var id: String
	{
		path
	}
	var path: String
	{
		newPath ?? oldPath ?? "Unknown path"
	}
	let oldPath: String?
	let newPath: String?
	let kind: GitComparisonChangeKind
	let additions: Int
	let deletions: Int
	let isBinary: Bool
	let patch: String
	let hunks: [GitComparisonHunk]
}

/// Immutable comparison bytes. Presentation filters must never modify this payload.
struct GitComparisonSnapshot: Equatable, Sendable
{
	let request: GitComparisonRequest
	let id: String
	let resolvedBase: String
	let resolvedTarget: String
	let patch: Data
	let files: [GitComparisonFile]
	var usesReportedEditFallback: Bool = false
	var additions: Int
	{
		files.reduce(0)
		{
			$0 + $1.additions
		}
	}
	var deletions: Int
	{
		files.reduce(0)
		{
			$0 + $1.deletions
		}
	}

	/// macOS base64 -D decodes the exact unfiltered bytes. This is only clipboard text.
	var copyCommand: String?
	{
		guard !usesReportedEditFallback, !patch.isEmpty, patch.count <= 8 * 1024 * 1024,
				!files.contains(where:
				{
					$0.isBinary
				})
		else
		{
			return nil
		}
		let root = request.repositoryRoot.replacingOccurrences(
			of: "'",
			with: "'\"'\"'"
		)
		return "printf '%s' '" + patch.base64EncodedString()
			+ "' | base64 -D | git -C '" + root + "' apply"
			+ (request.reportedChanges == nil ? "" : " --unidiff-zero")
	}
}
