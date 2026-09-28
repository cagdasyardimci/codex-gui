import Foundation

/// A reported change belongs to one Codex turn, even when the repository has moved on.
struct ReviewTurn
{
	let threadID: String
	let turnID: String
	let files: [ReviewFile]
	let validations: [ReviewValidation]
	/// Identity of the changes reported through this turn. This is not a Git revision.
	let codeStateID: String
	let hasUnknownEarlierHistory: Bool
}

enum ReviewFileKind: String, Equatable
{
	case added
	case modified
	case deleted
	case renamed
	case binary
	case unsupported
}

struct ReviewFile
{
	let path: String
	let previousPath: String?
	/// Reported destination from `kind.move_path`, when present.
	let reportedMovePath: String?
	let kind: ReviewFileKind
	let hunks: [ReviewHunk]
	let diff: String
	let fingerprint: String
	let explanation: String?

	var displayName: String
	{
		if let previousPath, previousPath != path
		{
			return "\(previousPath) → \(path)"
		}
		return path
	}
}

struct ReviewHunk
{
	/// Stable within one file version, including duplicate hunk headers.
	let id: String
	let header: String
	let text: String
	let fingerprint: String
}

enum ReviewValidationOutcome: String, Equatable
{
	case succeeded
	case failed
	case unknown
	case unobserved
}

enum ReviewValidationCurrency: String, Equatable
{
	/// Later reported file changes make this result inapplicable to the selected turn's final
	/// state.
	case outdated
	/// No later edits were reported, but the current repository state was not verified.
	case uncertain
}

struct ReviewValidation
{
	let threadID: String
	let turnID: String
	let itemID: String
	let command: String
	let cwd: String?
	let output: String?
	let exitCode: Int?
	let outcome: ReviewValidationOutcome
	let currency: ReviewValidationCurrency
	/// Identity of reported changes preceding the command, not proof of its test coverage.
	let codeStateID: String
	let hasUnknownEarlierHistory: Bool

	var scopeDescription: String
	{
		let history =
			hasUnknownEarlierHistory
				? "Earlier turns are not loaded. " : ""
		return history
			+ "Code state is based on reported changes, not verified repository contents. "
			+ "What this command checked is unknown."
	}
}

enum ReviewRequestKind: Equatable
{
	case ask
	case revision
}

/// A reference is serialized into the draft so its origin survives later turns and edits.
struct ReviewReference: Hashable
{
	let threadID: String
	let turnID: String
	let path: String
	let hunkID: String?

	init(
		threadID: String,
		turnID: String,
		file: ReviewFile,
		hunk: ReviewHunk? = nil
	)
	{
		self.threadID = threadID
		self.turnID = turnID
		self.path = file.path
		self.hunkID = hunk?.id
	}

	func prompt(
		for kind: ReviewRequestKind,
		file: ReviewFile,
		hunk: ReviewHunk? = nil
	) -> String
	{
		let instruction =
			kind == .ask ? "Question about this change:" : "Please revise this change:"
		var context = [
			instruction,
			"Origin thread: \(threadID)",
			"Origin turn: \(turnID)",
			"File: \(file.path)",
		]
		if let previousPath = file.previousPath
		{
			context.append("Previous path: \(previousPath)")
		}
		context.append("Change type: \(file.kind.rawValue)")
		context.append("File change fingerprint: \(file.fingerprint)")
		if let hunk
		{
			context.append("Section: \(hunk.id) \(hunk.header)")
			context.append("Section context:\n\(hunk.text)")
		}
		else
		{
			context.append("File context:\n\(file.diff)")
		}
		return context.joined(separator: "\n") + "\n\n"
	}
}
