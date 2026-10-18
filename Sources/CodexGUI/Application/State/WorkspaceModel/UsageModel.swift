import Foundation

struct UsageRefreshOperation
{
	let context: OperationContext
	var readsStarted: Int
}

struct UsageModel
{
	var snapshot: AccountRateLimitsSnapshot?
	var fetchedAt: Date?
	var error: String?
	var needsRefresh = true
	var pendingRefresh: UsageRefreshOperation?
	var refreshPending = false
	var freshnessDeadline: Date?
	var pendingDeadline: UsageDeadlineOperation?

	/// Time enters through an action or selector argument, never a model clock read.
	func isStale(
		isConnected: Bool,
		now: Date
	) -> Bool
	{
		guard isConnected, !needsRefresh, error == nil, fetchedAt != nil,
				let freshnessDeadline
		else
		{
			return true
		}
		return now >= freshnessDeadline
	}
}
