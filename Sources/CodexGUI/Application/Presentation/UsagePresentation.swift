import Foundation

struct UsagePresentation: Equatable
{
	let owner: FeaturePresentationOwner?
	let limits: AccountRateLimitsSnapshot?
	let refreshedAt: Date?
	let isStale: Bool
	let unavailableReason: String?

	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: ownerIdentity
		)
		limits = snapshot.usage
		refreshedAt = snapshot.usageFetchedAt
		isStale = snapshot.usageIsStale
		unavailableReason = snapshot.usageError
	}

	init(
		limits: AccountRateLimitsSnapshot?,
		refreshedAt: Date?,
		isStale: Bool,
		unavailableReason: String?
	)
	{
		owner = nil
		self.limits = limits
		self.refreshedAt = refreshedAt
		self.isStale = isStale
		self.unavailableReason = unavailableReason
	}
}
