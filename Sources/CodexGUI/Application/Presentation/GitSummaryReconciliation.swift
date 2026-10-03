import Foundation

/// Validates immutable canonical projections; never recounts diffs or owns comparison records.
struct GitSummaryReconciliation
{
	private(set) var owner: FeaturePresentationOwner?
	private(set) var projection: GitReviewSummaryProjection?
	private var highestRevision = -1

	mutating func select(_ owner: FeaturePresentationOwner)
	{
		guard self.owner != owner
		else
		{
			return
		}
		self.owner = owner
		projection = nil
		highestRevision = -1
	}

	@discardableResult
	mutating func accept(
		_ incoming: GitReviewSummaryProjection?,
		canonical: GitReviewSummaryProjection?
	) -> Bool
	{
		guard incoming == canonical
		else
		{
			return false
		}
		guard let incoming
		else
		{
			projection = nil
			return true
		}
		guard incoming.owner == owner, incoming.revision >= highestRevision
		else
		{
			return false
		}
		if incoming.revision == highestRevision
		{
			return incoming == projection
		}
		if incoming.totals.value != nil
		{
			guard incoming.comparisonID != nil, incoming.snapshotScope != nil
			else
			{
				return false
			}
		}
		if case .available = incoming.totals,
			incoming.snapshotScope != incoming.scope
		{
			return false
		}
		projection = incoming
		highestRevision = incoming.revision
		return true
	}

	func section(for owner: FeaturePresentationOwner) -> SummarySection<SummaryChangeTotals>
	{
		guard owner == self.owner, let projection
		else
		{
			return .unavailable("Open Changes to load a repository comparison")
		}
		return projection.totals
	}

	var scopeDescription: String?
	{
		guard let projection
		else
		{
			return nil
		}
		if projection.totals.value != nil
		{
			switch projection.totals
			{
			case .loading, .failed:
				return projection.scope.title + "; previous "
					+ (projection.snapshotScope?.title ?? "unknown scope") + " totals (stale)"
			case .available, .unavailable: break
			}
		}
		return projection.scope.title
	}
}
