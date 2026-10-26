import Foundation

/// Display values keep token activity separate from the account's remaining plan allowance.
enum SettingsUsagePresentation
{
	struct Limit
	{
		let title: String
		let accessibilityLabel: String
		let remaining: Double?
		let reset: String
	}

	struct DailyBucket: Equatable
	{
		let date: String
		let tokens: Int64
	}

	static func dailyBuckets(_ usage: [String: Any]?) -> [DailyBucket]
	{
		let raw = usage?["dailyUsageBuckets"] as? [[String: Any]] ?? []
		let days = raw.compactMap
		{
			bucket -> DailyBucket? in
			guard let date = bucket["startDate"] as? String,
					let number = bucket["tokens"] as? NSNumber,
					!date.isEmpty, number.int64Value >= 0
			else
			{
				return nil
			}
			return DailyBucket(
				date: date,
				tokens: number.int64Value
			)
		}
		return Array(days.sorted
		{
			$0.date < $1.date
		}.suffix(31))
	}

	static func dailyChartFractions(_ days: [DailyBucket]) -> [Double]
	{
		guard let peak = days.map(\.tokens).max(), peak > 0
		else
		{
			return Array(
				repeating: 0,
				count: days.count
			)
		}
		return days.map
		{
			Double($0.tokens) / Double(peak)
		}
	}

	static func limits(
		_ snapshot: AccountRateLimitsSnapshot?,
		now: Date
	) -> [Limit]
	{
		guard let snapshot
		else
		{
			return []
		}
		let buckets = snapshot.rateLimitsByLimitId.flatMap
		{
			$0.isEmpty ? nil : $0
		}
		?? ["codex": snapshot.rateLimits]
		return buckets.keys.sorted().flatMap
		{
			key -> [Limit] in
			guard let bucket = buckets[key]
			else
			{
				return []
			}
			let name = bucket.limitName ?? (key == "codex" ? "Codex" : key)
			return [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap
			{
				kind, window in
				guard let window
				else
				{
					return nil
				}
				let duration = windowTitle(
					window.windowDurationMins,
					kind: kind
				)
				return Limit(
					title: key == "codex" ? duration : "\(name) · \(duration)",
					accessibilityLabel: "\(name) \(duration)",
					remaining: window.usedPercent.isFinite
						? max(
							0,
							min(
								100,
								100 - window.usedPercent
							)
						) : nil,
					reset: resetDescription(
						window.resetsAt,
						now: now
					)
				)
			}
		}
	}

	static func windowTitle(
		_ minutes: Int?,
		kind: String
	) -> String
	{
		switch minutes
		{
		case 10080: return "Weekly limit"
		case 300: return "5-hour limit"
		case let value? where value > 0 && value % 1440 == 0: return "\(value / 1440)-day limit"
		case let value? where value > 0 && value % 60 == 0: return "\(value / 60)-hour limit"
		case let value? where value > 0: return "\(value)-minute limit"
		default: return kind == "primary" ? "Usage limit" : "Additional limit"
		}
	}

	static func percent(_ value: Double) -> String
	{
		value.formatted(.number.precision(.fractionLength(0 ... 1))) + "%"
	}

	static func resetDescription(
		_ date: Date?,
		now: Date
	) -> String
	{
		guard let date
		else
		{
			return "Reset time unavailable"
		}
		let seconds = date.timeIntervalSince(now)
		guard seconds > 0
		else
		{
			return "Reset pending refresh"
		}
		let minutes = max(
			1,
			Int(ceil(seconds / 60))
		)
		if minutes >= 1440
		{
			return "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h"
		}
		if minutes >= 60
		{
			return "Resets in \(minutes / 60)h \(minutes % 60)m"
		}
		return "Resets in \(minutes)m"
	}

	static func planTitle(_ type: String?) -> String
	{
		guard let type, !type.isEmpty, type != "unknown"
		else
		{
			return "Plan unavailable"
		}
		let names = ["free": "Free",
						"go": "Go",
						"plus": "Plus",
						"pro": "Pro",
						"team": "Team",
						"business": "Business",
						"enterprise": "Enterprise",
						"edu": "Edu"]
		return "ChatGPT " +
			(names[type] ?? type.replacingOccurrences(
				of: "_",
				with: " "
			).capitalized)
	}

	static func credits(_ snapshot: AccountRateLimitsSnapshot?) -> String
	{
		let credits = snapshot?.rateLimits.credits
			?? snapshot?.rateLimitsByLimitId?.sorted
			{
				$0.key < $1.key
			}
			.compactMap
			{
				$0.value.credits
			}.first
		guard let credits
		else
		{
			return "Credit balance unavailable"
		}
		if credits.unlimited
		{
			return "Unlimited credits"
		}
		guard let balance = credits.balance
		else
		{
			return "Credit balance unavailable"
		}
		let value = Decimal(
			string: balance,
			locale: Locale(identifier: "en_US_POSIX")
		)
		return (value?.formatted(.number) ?? balance) + " credits remaining"
	}

	static func activity(_ usage: [String: Any]?) -> [(String, String)]
	{
		let summary = usage?["summary"] as? [String: Any] ?? [:]
		return [("lifetimeTokens", "Lifetime tokens"),
				("peakDailyTokens", "Peak daily tokens"),
				("currentStreakDays", "Current streak"),
				("longestStreakDays", "Longest streak"),
				("longestRunningTurnSec", "Longest task")].map
		{
			key, label in
			guard let number = summary[key] as? NSNumber
			else
			{
				return (label, "Unavailable")
			}
			let count = number.int64Value
			if key.hasSuffix("Days")
			{
				return (label, "\(count.formatted()) days")
			}
			if key == "longestRunningTurnSec"
			{
				let hours = count / 3600
				let minutes = (count % 3600) / 60
				return (label, hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(count % 60)s")
			}
			return (label, count.formatted())
		}
	}
}
