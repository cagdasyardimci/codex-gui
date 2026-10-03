import Foundation

/// Pinned summary consumes this owner-scoped projection in its aggregate publication.
/// `comparisonID` is also the navigation token; paths alone never select another snapshot.
struct GitReviewSummaryProjection: Equatable
{
	let owner: FeaturePresentationOwner
	let revision: Int
	let scope: GitComparisonScope
	let comparisonID: String?
	let snapshotScope: GitComparisonScope?
	let totals: SummarySection<SummaryChangeTotals>
}
