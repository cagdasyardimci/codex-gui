import Foundation
import Testing

@testable import CodexGUI

struct GitCodeViewportTests
{
	@Test func narrowViewportKeepsReadableFiniteSourceGeometry()
	{
		let viewport = GitCodeViewport(
			viewportWidth: 150,
			measuredCodeWidth: 300,
			documentHeight: 97
		)
		#expect(viewport.documentSize == CGSize(
			width: 300,
			height: 97
		))
		#expect(viewport.containerSize == CGSize(
			width: 280,
			height: 97
		))
	}

	@Test func resizeUsesViewportWithoutWrappingLongLines()
	{
		let narrow = GitCodeViewport(
			viewportWidth: 400,
			measuredCodeWidth: 1200,
			documentHeight: 780
		)
		let wide = GitCodeViewport(
			viewportWidth: 1400,
			measuredCodeWidth: 1200,
			documentHeight: 780
		)
		#expect(narrow.documentSize.width == 1200)
		#expect(wide.documentSize.width == 1400)
		#expect(narrow.documentSize.height == wide.documentSize.height)
		#expect(wide.containerSize.width == 1380)
	}

	@Test func emptyOrInvalidMeasurementsCannotCreateUnboundedTextGeometry()
	{
		for width in [CGFloat.zero, -10, .infinity, .nan]
		{
			let viewport = GitCodeViewport(
				viewportWidth: width,
				measuredCodeWidth: width,
				documentHeight: width
			)
			#expect(viewport.documentSize.width.isFinite)
			#expect(viewport.documentSize.height.isFinite)
			#expect(viewport.containerSize.width == 220)
			#expect(viewport.containerSize.height >= 1)
		}
	}
}
