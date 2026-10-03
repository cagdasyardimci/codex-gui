import Foundation
import Testing

@testable import CodexGUI

struct GitCodeViewportTests
{
	@Test func narrowViewportKeepsReadableFiniteSourceGeometry()
	{
		let value = GitCodeViewport(
			viewportWidth: 150,
			measuredCodeWidth: 300,
			documentHeight: 97
		)
		#expect(value.documentSize == CGSize(
			width: 300,
			height: 97
		))
		#expect(value.containerSize == CGSize(
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
			let value = GitCodeViewport(
				viewportWidth: width,
				measuredCodeWidth: width,
				documentHeight: width
			)
			#expect(value.documentSize.width.isFinite)
			#expect(value.documentSize.height.isFinite)
			#expect(value.containerSize.width == 220)
			#expect(value.containerSize.height >= 1)
		}
	}
}
