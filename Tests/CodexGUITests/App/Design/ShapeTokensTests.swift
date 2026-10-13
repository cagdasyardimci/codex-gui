import Foundation
import Testing

@testable import CodexGUI

@Suite struct ShapeTokensTests
{
	@Test func radiusUsesItsSuppliedControlHeight()
	{
		#expect(ShapeTokens.Composer.controlRadius(forControlHeight: 32) == 16)
		#expect(ShapeTokens.Composer.controlRadius(
			forControlHeight: LayoutTokens.composer.controlHeight
		) == 14)
		#expect(ShapeTokens.Composer.cornerRadius == 24)
	}

	@Test func controlRolesRemainIndependentOfEqualDimensions()
	{
		#expect(ShapeTokens.TabControls.radius(for: .close) == 10)
		#expect(ShapeTokens.TabControls.radius(for: .standard) == 12.5)
	}
}
