import Foundation

enum GitReviewAction
{
	case activate(
		owner: FeaturePresentationOwner,
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure?
	)
	case updateContext(
		lastTurnID: String?,
		baselineRevision: Int,
		baselineFailure: GitComparisonFailure?
	)
	case close
	case setReportedChanges([FileChange]?)
	case reload
	case repositoryChanged
	case selectScope(GitComparisonScope)
	case setRevisions(
		base: String,
		target: String
	)
	case setFilter(String)
	case selectFile(String)
	case toggleDirectory(String)
	case expandGap(String)
	case setOptions(GitDiffPresentationOptions)
	case poll(FeaturePresentationOwner)
	case received(
		GitComparisonResult,
		request: GitComparisonRequest
	)
}
