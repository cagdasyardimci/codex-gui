import Foundation
import Testing

@testable import CodexGUI

@Suite struct ShapeTokensTests
{
	@Test func composerRadiusUsesTheSuppliedHeight()
	{
		let tallerComposer = LayoutTokens.Composer(controlHeight: 32)
		#expect(tallerComposer.isValid)
		#expect(ShapeTokens.Composer.controlRadius(
			forControlHeight: tallerComposer.controlHeight
		) == 16)
		#expect(LayoutTokens.composer.controlHeight == 28)
		#expect(ShapeTokens.Composer.controlRadius(
			forControlHeight: LayoutTokens.composer.controlHeight
		) == 14)
		#expect(ShapeTokens.Composer.cornerRadius == 22)
	}

	@Test func controlRolesRemainIndependentOfEqualDimensions()
	{
		#expect(ShapeTokens.TabControls.radius(for: .close) == 10)
		#expect(ShapeTokens.TabControls.radius(for: .standard) == 12.5)
	}
}
