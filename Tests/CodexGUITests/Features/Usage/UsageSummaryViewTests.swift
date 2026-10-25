import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct UsageSummaryViewTests
{

	@Test func usageDetailsPreserveSectionAndLimitIdentifierOrder() throws
	{
		_ = NSApplication.shared
		let view = UsageSummaryView()
		let snapshot = try #require(AccountRateLimitsSnapshot(json: [
			"rateLimits": [
				"limitName": "Account limits",
				"planType": "plus",
				"primary": [
					"usedPercent": 25.4,
					"windowDurationMins": 300,
					"resetsAt": 1_800_000_000,
				],
				"secondary": ["usedPercent": 42.6],
				"credits": ["hasCredits": true, "unlimited": true],
			],
			"rateLimitsByLimitId": [
				"z-limit": ["primary": ["usedPercent": 60.0]],
				"a-limit": [
					"limitName": "Named limit",
					"secondary": ["usedPercent": 10.0],
				],
			],
			"rateLimitResetCredits": ["availableCount": 2],
		]))
		let button = try #require(view.subviews.compactMap
		{
			$0 as? NSButton
		}.first)
		let refreshedAt = Date(timeIntervalSince1970: 1_799_827_200)
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		let displayedFetchDate = formatter.string(from: refreshedAt)
		let displayedResetDate = formatter.string(from: Date(timeIntervalSince1970: 1_800_000_000))
		#expect(displayedFetchDate != displayedResetDate)

		view.render(
			limits: snapshot,
			refreshedAt: refreshedAt,
			isStale: true,
			unavailableReason: "Refresh failed"
		)

		#expect(button.title == "Usage 25% · stale")
		#expect(button.toolTip == [
			"Account limits",
			"Plan: plus",
			"Primary: 25% used over 300 min · resets \(displayedResetDate)",
			"Secondary: 43% used",
			"Named limit:",
			"Primary: unavailable",
			"Secondary: 10% used",
			"z-limit:",
			"Primary: 60% used",
			"Secondary: unavailable",
			"Credits: Unlimited",
			"Reset credits available: 2",
			"Fetched: \(displayedFetchDate)",
			"Stale: backend has not confirmed a recent value",
			"Refresh failed",
		].joined(separator: "\n"))
	}

}
