import Foundation

struct GitSummaryState
{
	var owner: FeaturePresentationOwner?
	var generation = 0
	var revision = 0
	var pendingRequest: GitComparisonRequest?
	var projection: GitReviewSummaryProjection?
}
