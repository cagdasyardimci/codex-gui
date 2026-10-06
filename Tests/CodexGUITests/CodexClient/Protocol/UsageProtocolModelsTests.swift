import Foundation
import Testing

@testable import CodexGUI

struct UsageProtocolModelsTests
{
	@Test func rateLimitWindowPreservesReportedResetTimeAndUnavailableWindows() throws
	{
		let snapshot = try #require(
			AccountRateLimitsSnapshot(json: [
				"rateLimits": [
					"limitId": "codex",
					"limitName": NSNull(),
					"primary": [
						"usedPercent": 25.5,
						"windowDurationMins": 15,
						"resetsAt": 1_730_947_200,
					],
					"secondary": NSNull(),
					"credits": NSNull(),
					"planType": "plus",
				],
				"rateLimitsByLimitId": NSNull(),
				"accountId": NSNull(),
			])
		)
		#expect(snapshot.rateLimits.limitId == "codex")
		#expect(snapshot.rateLimits.primary?.usedPercent == 25.5)
		#expect(snapshot.rateLimits.primary?.windowDurationMins == 15)
		#expect(snapshot.rateLimits.primary?.resetsAt?.timeIntervalSince1970 == 1_730_947_200)
		#expect(snapshot.rateLimits.secondary == nil)
		#expect(snapshot.rateLimits.credits == nil)
		#expect(snapshot.rateLimitsByLimitId == nil)
	}

	@Test func resetCreditSummaryPreservesCountAndOptionalDetails() throws
	{
		let details = try #require(
			RateLimitResetCreditsSummary(json: [
				"availableCount": 2,
				"credits": [
					[
						"id": "credit-1",
						"resetType": "codexRateLimits",
						"status": "available",
						"grantedAt": 1_781_654_400,
						"expiresAt": NSNull(),
						"title": "Rate-limit reset",
						"description": NSNull(),
					]
				],
			])
		)
		#expect(details.availableCount == 2)
		#expect(details.credits?.count == 1)
		#expect(details.credits?.first?.expiresAt == nil)
		#expect(details.credits?.first?.grantedAt.timeIntervalSince1970 == 1_781_654_400)

		let countOnly = try #require(
			RateLimitResetCreditsSummary(json: ["availableCount": 2, "credits": NSNull()])
		)
		#expect(countOnly.credits == nil)
	}

}
