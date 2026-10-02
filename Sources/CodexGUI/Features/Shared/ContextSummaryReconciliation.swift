import Foundation

struct ContextSummaryReconciliation
{
	private(set) var owner: FeaturePresentationOwner?
	private(set) var revision = -1
	private(set) var sections = ContextSummarySections()

	mutating func select(_ owner: FeaturePresentationOwner)
	{
		guard self.owner != owner
		else
		{
			return
		}
		self.owner = owner
		revision = -1
		sections = ContextSummarySections()
	}

	@discardableResult
	mutating func accept(_ update: ContextSummaryUpdate) -> Bool
	{
		guard update.owner == owner, update.revision > revision
		else
		{
			return false
		}
		revision = update.revision
		sections = update.sections
		return true
	}
}
