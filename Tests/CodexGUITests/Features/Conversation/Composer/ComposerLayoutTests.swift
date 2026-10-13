import Foundation
import Testing

@testable import CodexGUI

@Suite struct ComposerLayoutTests
{
	@Test func footerInsetDoesNotChangeTheEditorInsetOrThresholdCoordinateSpace()
	{
		let metrics = LayoutTokens.Composer(footerHorizontalInset: 12)
		let layout = ComposerLayout(metrics: metrics)
		#expect(metrics.isValid)
		#expect(metrics.editorHorizontalInset == 12)
		#expect(metrics.nestedEditorWidthAdjustment == 0)
		#expect(layout.usesCompactFooter(innerWidth: 456 - 2 * 12))
		#expect(!layout.usesCompactFooter(innerWidth: 464 - 2 * 12))
		#expect(LayoutTokens.Composer(footerHorizontalInset: 16)
			.nestedEditorWidthAdjustment == 0)
		#expect(LayoutTokens.Composer(footerHorizontalInset: 16)
			.nestedFooterWidthAdjustment == -8)
		#expect(layout.desiredEditorHeight(
			contentHeight: 600,
			viewportHeight: 881
		) == 220.25)
	}

	@Test func footerContractRejectsAControlTallerThanItsRequiredActionRow()
	{
		let layout = ComposerLayout()
		#expect(layout.footerHeight(
			compact: false,
			leadingHeight: 28,
			preferenceHeight: 28,
			actionHeight: 28
		) == 28)
		#expect(layout.footerHeight(
			compact: true,
			leadingHeight: 28,
			preferenceHeight: 28,
			actionHeight: 28
		) == 60)
		#expect(layout.footerHeight(
			compact: true,
			leadingHeight: 28,
			preferenceHeight: 32,
			actionHeight: 28
		) == nil)
		#expect(layout.footerHeight(
			compact: false,
			leadingHeight: 32,
			preferenceHeight: 28,
			actionHeight: 28
		) == nil)
		#expect(layout.footerHeight(
			compact: true,
			leadingHeight: 32,
			preferenceHeight: 28,
			actionHeight: 28
		) == 64)
	}
}
