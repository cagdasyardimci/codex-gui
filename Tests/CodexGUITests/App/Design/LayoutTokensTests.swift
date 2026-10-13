import Foundation
import Testing

@testable import CodexGUI

@Suite struct LayoutTokensTests
{
	@Test func existingDefaultsRetainNativeLayoutContracts()
	{
		#expect(LayoutTokens.Tabs.headerHeight == 28)
		#expect(LayoutTokens.Tabs.tabWidth == 180)
		#expect(LayoutTokens.Tabs.controlSize == 24)
		#expect(LayoutTokens.window.toolsMinimumWidth == 320)
		#expect(LayoutTokens.composer.minimumHeight == 49)
		#expect(LayoutTokens.Composer.maximumEditorHeight == 160)
		#expect(LayoutTokens.composer.preferenceToActionSpacing == 16)
	}

	@Test func independentInsetsResolveWithoutDuplicatedAllowances()
	{
		let metrics = LayoutTokens.Composer(
			editorHorizontalInset: 8,
			footerHorizontalInset: 12
		)
		#expect(metrics.isValid)
		#expect(metrics.stackHorizontalInset == 8)
		#expect(metrics.nestedEditorWidthAdjustment == 0)
		#expect(metrics.nestedFooterWidthAdjustment == -8)
	}

	@Test func tabRoleValidationUsesExplicitConfiguration()
	{
		let metrics = LayoutTokens.TabContent(
			leadingInset: 40,
			trailingInset: 7,
			minimumWidth: 88,
			maximumWidth: 238,
			closeControlSize: 20,
			moreControlSize: 28
		)
		#expect(metrics.isValid)
		#expect(metrics.effectiveMinimum(for: .ordinary) == 91)
		#expect(metrics.effectiveMinimum(for: .conversation) == 99)
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
