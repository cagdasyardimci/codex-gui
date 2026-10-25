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

}
