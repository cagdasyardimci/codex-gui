import Foundation

struct RateLimitWindow: Equatable
{
	let usedPercent: Double
	let windowDurationMins: Int?
	let resetsAt: Date?

	init?(json: [String: Any])
	{
		guard let usedPercent = (json["usedPercent"] as? NSNumber)?.doubleValue
		else
		{
			return nil
		}
		self.usedPercent = usedPercent
		self.windowDurationMins = (json["windowDurationMins"] as? NSNumber)?.intValue
		self.resetsAt = (json["resetsAt"] as? NSNumber)
			.map
			{
				Date(timeIntervalSince1970: $0.doubleValue)
			}
	}
}

struct RateLimitCredits: Equatable
{
	let hasCredits: Bool
	let unlimited: Bool
	let balance: String?

	init?(json: [String: Any])
	{
		guard let hasCredits = json["hasCredits"] as? Bool,
				let unlimited = json["unlimited"] as? Bool
		else
		{
			return nil
		}
		self.hasCredits = hasCredits
		self.unlimited = unlimited
		self.balance = json["balance"] as? String
	}
}

struct SpendControlLimit: Equatable
{
	let limit: String
	let used: String
	let remainingPercent: Double
	let resetsAt: Date

	init?(json: [String: Any])
	{
		guard let limit = json["limit"] as? String,
				let used = json["used"] as? String,
				let remainingPercent = (json["remainingPercent"] as? NSNumber)?.doubleValue,
				let resetSeconds = (json["resetsAt"] as? NSNumber)?.doubleValue
		else
		{
			return nil
		}
		self.limit = limit
		self.used = used
		self.remainingPercent = remainingPercent
		self.resetsAt = Date(timeIntervalSince1970: resetSeconds)
	}
}

struct RateLimitSnapshot: Equatable
{
	let limitId: String?
	let limitName: String?
	let primary: RateLimitWindow?
	let secondary: RateLimitWindow?
	let credits: RateLimitCredits?
	let individualLimit: SpendControlLimit?
	let spendControlReached: Bool?
	let planType: String?
	let rateLimitReachedType: String?

	init(json: [String: Any])
	{
		self.limitId = json["limitId"] as? String
		self.limitName = json["limitName"] as? String
		self.primary = (json["primary"] as? [String: Any]).flatMap(RateLimitWindow.init(json:))
		self.secondary = (json["secondary"] as? [String: Any]).flatMap(RateLimitWindow.init(json:))
		self.credits = (json["credits"] as? [String: Any]).flatMap(RateLimitCredits.init(json:))
		self.individualLimit = (json["individualLimit"] as? [String: Any])
			.flatMap(SpendControlLimit.init(json:))
		self.spendControlReached = json["spendControlReached"] as? Bool
		self.planType = json["planType"] as? String
		self.rateLimitReachedType = json["rateLimitReachedType"] as? String
	}
}

struct RateLimitResetCredit: Equatable
{
	let id: String
	let resetType: String
	let status: String
	let grantedAt: Date
	let expiresAt: Date?
	let title: String?
	let description: String?

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String,
				let resetType = json["resetType"] as? String,
				let status = json["status"] as? String,
				let grantedSeconds = (json["grantedAt"] as? NSNumber)?.doubleValue
		else
		{
			return nil
		}
		self.id = id
		self.resetType = resetType
		self.status = status
		self.grantedAt = Date(timeIntervalSince1970: grantedSeconds)
		self.expiresAt = (json["expiresAt"] as? NSNumber)
			.map
			{
				Date(timeIntervalSince1970: $0.doubleValue)
			}
		self.title = json["title"] as? String
		self.description = json["description"] as? String
	}
}

struct RateLimitResetCreditsSummary: Equatable
{
	let availableCount: Int64
	let credits: [RateLimitResetCredit]?

	init?(json: [String: Any])
	{
		guard let availableCount = (json["availableCount"] as? NSNumber)?.int64Value
		else
		{
			return nil
		}
		self.availableCount = availableCount
		if let rawCredits = json["credits"] as? [[String: Any]]
		{
			let credits = rawCredits.compactMap(RateLimitResetCredit.init(json:))
			guard credits.count == rawCredits.count
			else
			{
				return nil
			}
			self.credits = credits
		}
		else
		{
			self.credits = nil
		}
	}
}

struct AccountRateLimitsSnapshot: Equatable
{
	let rateLimits: RateLimitSnapshot
	let rateLimitsByLimitId: [String: RateLimitSnapshot]?
	let rateLimitResetCredits: RateLimitResetCreditsSummary?
	let accountId: String?

	init?(json: [String: Any])
	{
		guard let rateLimits = json["rateLimits"] as? [String: Any]
		else
		{
			return nil
		}
		self.rateLimits = RateLimitSnapshot(json: rateLimits)
		self.rateLimitsByLimitId = (json["rateLimitsByLimitId"] as? [String: [String: Any]])?
			.mapValues(RateLimitSnapshot.init(json:))
		self.rateLimitResetCredits = (json["rateLimitResetCredits"] as? [String: Any])
			.flatMap(RateLimitResetCreditsSummary.init(json:))
		self.accountId = json["accountId"] as? String
	}
}
