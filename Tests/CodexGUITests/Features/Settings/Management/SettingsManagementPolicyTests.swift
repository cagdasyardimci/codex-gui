import Testing
@testable import CodexGUI

struct SettingsManagementPolicyTests
{
	@Test func dynamicKeysRemainOneTOMLComponent()
	{
		#expect(SettingsManagementPolicy.quotedKey("plugin.tool") == "\"plugin.tool\"")
		#expect(SettingsManagementPolicy.quotedKey("quoted\"path\\hook")
			== "\"quoted\\\"path\\\\hook\"")
	}

	@Test(arguments: [0, -1])
	func exhaustedWindowCannotRedeemWithoutPositiveCredit(available: Int)
	{
		#expect(!SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": ["availableCount": available],
			"rateLimits": ["primary": ["usedPercent": 100]],
		]))
	}

	@Test func usageResetRequiresCreditAndNearlyExhaustedWindow()
	{
		let credit: [String: Any] = ["availableCount": 1]
		#expect(!SettingsManagementPolicy.canReset([:]))
		#expect(!SettingsManagementPolicy.canReset(["rateLimitResetCredits": credit]))
		let window: [String: Any] = ["primary": ["usedPercent": 90]]
		#expect(!SettingsManagementPolicy.canReset(["rateLimits": window]))
		#expect(SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": credit,
			"rateLimits": window,
		]))
		#expect(!SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": credit,
			"rateLimits": ["primary": ["usedPercent": 89]],
		]))
		#expect(SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": credit,
			"rateLimitsByLimitId": ["codex": ["secondary": ["usedPercent": 100]]],
		]))
		#expect(SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": credit,
			"rateLimitsByLimitId": [:],
			"rateLimits": ["primary": ["usedPercent": 90.5]],
		]))
		#expect(!SettingsManagementPolicy.canReset([
			"rateLimitResetCredits": credit,
			"rateLimits": ["primary": ["usedPercent": Double.infinity]],
		]))
	}
}
