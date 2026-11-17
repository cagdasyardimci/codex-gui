import Foundation

struct ResultFeedbackTarget: Equatable, Hashable, Sendable
{
	let threadID: String
	let turnID: String
}

enum ResultFeedbackRating: String, Equatable, Sendable
{
	case good = "good_result"
	case bad = "bad_result"
}

struct ResultFeedbackSubmission: Equatable, Sendable
{
	let target: ResultFeedbackTarget
	let rating: ResultFeedbackRating
}

struct ResultFeedbackOperation: Equatable, Sendable
{
	let context: OperationContext
	let submission: ResultFeedbackSubmission
}

enum ResultFeedbackOutcome
{
	case submitted
	case failed(
		OperationFailure,
		unavailable: Bool
	)
}

struct ResultFeedbackModel: Equatable
{
	var workspace: WorkspaceIdentity?
	var generation: Int?
	var pending: ResultFeedbackOperation?
	var submitted: [ResultFeedbackTarget: ResultFeedbackRating] = [:]
	var uncertain: Set<ResultFeedbackTarget> = []
	var unavailable = false
	var lastFailure: OperationFailure?
}

struct ResultFeedbackPresentation: Equatable
{
	var canSubmit: Set<ResultFeedbackTarget> = []
	var pending: ResultFeedbackTarget?
	var submitted: [ResultFeedbackTarget: ResultFeedbackRating] = [:]
	var uncertain: Set<ResultFeedbackTarget> = []
}

enum ResultFeedbackAction
{
	case requested(ResultFeedbackOperation)
	case finished(
		ResultFeedbackOperation,
		ResultFeedbackOutcome
	)
}
