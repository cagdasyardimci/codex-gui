import Foundation

enum GitReviewEffect
{
	case cancelRead
	case read(GitComparisonRequest)
	case stopPolling
	case startPolling(FeaturePresentationOwner)
}
