import Foundation

/// Uses the existing review pane's fingerprint/provenance comparison boundary.
struct ReviewPresentation: Equatable
{
	struct FileValue: Equatable
	{
		struct Hunk: Equatable
		{
			let id: String
			let header: String
			let text: String
			let fingerprint: String
		}
		let path: String
		let previousPath: String?
		let reportedMovePath: String?
		let kind: ReviewFileKind
		let hunks: [Hunk]
		let diff: String
		let fingerprint: String
		let explanation: String?

		init(_ file: ReviewFile)
		{
			path = file.path
			previousPath = file.previousPath
			reportedMovePath = file.reportedMovePath
			kind = file.kind
			hunks = file.hunks.map
			{
				Hunk(
					id: $0.id,
					header: $0.header,
					text: $0.text,
					fingerprint: $0.fingerprint
				)
			}
			diff = file.diff
			fingerprint = file.fingerprint
			explanation = file.explanation
		}
	}

	struct ValidationValue: Equatable
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
		let codeStateID: String
		let hasUnknownEarlierHistory: Bool

		init(_ validation: ReviewValidation)
		{
			threadID = validation.threadID
			turnID = validation.turnID
			itemID = validation.itemID
			command = validation.command
			cwd = validation.cwd
			output = validation.output
			exitCode = validation.exitCode
			outcome = validation.outcome
			currency = validation.currency
			codeStateID = validation.codeStateID
			hasUnknownEarlierHistory = validation.hasUnknownEarlierHistory
		}
	}

	struct TurnChoice: Equatable
	{
		let threadID: String
		let turnID: String
		let fileCount: Int
	}

	struct Key: Equatable
	{
		let owner: FeaturePresentationOwner
		let turns: [TurnChoice]
		let selectedReviewTurnID: String?
		let selectedReviewThreadID: String?
		let selectedReviewSourceTurnID: String?
		let selectedReviewCodeStateID: String?
		let hasUnknownEarlierHistory: Bool
		let files: [FileValue]
		let validations: [ValidationValue]
		let reviewedReferences: Set<ReviewReference>
		let legacyFiles: [ChangeFile]
		let legacyDiff: String
		var selectedThreadID: String?
		{
			owner.selectedThreadID
		}
	}

	let key: Key
	let projectPath: String?
	let selectedThreadID: String?
	let reviewTurns: [ReviewTurn]
	let selectedReviewTurnID: String?
	let selectedReview: ReviewTurn?
	let reviewedReferences: Set<ReviewReference>
	let changedFiles: [ChangeFile]
	let diff: String

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		let review = snapshot.selectedReview
		key = Key(
			owner: FeaturePresentationOwner(
				snapshot,
				storeIdentity: ownerIdentity
			),
			turns: snapshot.reviewTurns.map
			{
				TurnChoice(
					threadID: $0.threadID,
					turnID: $0.turnID,
					fileCount: $0.files.count
				)
			},
			selectedReviewTurnID: snapshot.selectedReviewTurnID,
			selectedReviewThreadID: review?.threadID,
			selectedReviewSourceTurnID: review?.turnID,
			selectedReviewCodeStateID: review?.codeStateID,
			hasUnknownEarlierHistory: review?.hasUnknownEarlierHistory ?? false,
			files: review?.files.map(FileValue.init) ?? [],
			validations: review?.validations.map(ValidationValue.init) ?? [],
			reviewedReferences: snapshot.reviewedReferences,
			legacyFiles: snapshot.changedFiles,
			legacyDiff: snapshot.diff
		)
		projectPath = snapshot.projectPath
		selectedThreadID = snapshot.selectedThreadID
		reviewTurns = snapshot.reviewTurns
		selectedReviewTurnID = snapshot.selectedReviewTurnID
		selectedReview = review
		reviewedReferences = snapshot.reviewedReferences
		changedFiles = snapshot.changedFiles
		diff = snapshot.diff
	}

	static func == (lhs: Self, rhs: Self) -> Bool
	{
		lhs.key == rhs.key
	}
}
