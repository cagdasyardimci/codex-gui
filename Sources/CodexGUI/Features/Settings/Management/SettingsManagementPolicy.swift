import Foundation

/// Shared validation for dynamic TOML keys and account reset availability.
enum SettingsManagementPolicy
{
	static func quotedKey(_ key: String) -> String
	{
		"\"" + key.replacingOccurrences(
			of: "\\",
			with: "\\\\"
		)
		.replacingOccurrences(
			of: "\"",
			with: "\\\""
		) + "\""
	}

	static func canReset(_ response: [String: Any]) -> Bool
	{
		let credits = response["rateLimitResetCredits"] as? [String: Any]
		guard let available = credits?["availableCount"] as? Int,
				available > 0
		else
		{
			return false
		}
		let buckets = (response["rateLimitsByLimitId"] as? [String: [String: Any]])
			.flatMap
			{
				$0.isEmpty ? nil : $0
			}
			?? ["codex": response["rateLimits"] as? [String: Any] ?? [:]]
		return buckets.values.contains
		{
			bucket in
			["primary", "secondary"].contains
			{
				key in
				guard let window = bucket[key] as? [String: Any],
						let used = (window["usedPercent"] as? NSNumber)?.doubleValue,
						used.isFinite
				else
				{
					return false
				}
				return used >= 90
			}
		}
	}
}
