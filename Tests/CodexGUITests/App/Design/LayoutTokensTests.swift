import Foundation
import Testing

@testable import CodexGUI

@Suite struct LayoutTokensTests
{

	@Test func tabMinimaAccountForBothTrailingRoles()
	{
		let metrics = LayoutTokens.TabContent(leadingInset: 40)
		#expect(metrics.isValid)
		#expect(metrics.effectiveMinimum(for: .ordinary) == 91)
		#expect(metrics.effectiveMinimum(for: .conversation) == 99)
		#expect(!LayoutTokens.TabContent(leadingInset: 200).isValid)
	}

	@Test func windowValidationIncludesSummaryFilesAndConversationReservations()
	{
		#expect(LayoutTokens.window.isValid(summaryPreferredWidth: 308))
		let incompatibleSummary = LayoutTokens.Window(
			reviewWidth: 350,
			reviewMinimumWidth: 340,
			reviewMaximumWidth: 360
		)
		#expect(!incompatibleSummary.isValid(summaryPreferredWidth: 308))
		#expect(!LayoutTokens.Window(filesMaximumWidth: 700)
			.isValid(summaryPreferredWidth: 308))
		#expect(!LayoutTokens.Window(conversationComfortableWidth: 200)
			.isValid(summaryPreferredWidth: 308))
		#expect(!LayoutTokens.Window(navigationMinimumWidth: .nan)
			.isValid(summaryPreferredWidth: 308))
	}
}
