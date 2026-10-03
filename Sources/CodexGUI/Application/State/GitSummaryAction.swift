import Foundation

enum GitSummaryAction
{
	case select(FeaturePresentationOwner)
	case loadIfNeeded(FeaturePresentationOwner)
	case refresh(FeaturePresentationOwner)
	case received(
		GitComparisonResult,
		request: GitComparisonRequest
	)
	case cancel
}
