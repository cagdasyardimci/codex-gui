import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct PinnedSummaryIconsTests
{
	@Test(arguments: PinnedSummaryIcons.Glyph.allCases)
	func vectorArtworkHasVisiblePixelsAndTransparentCorners(
		_ glyph: PinnedSummaryIcons.Glyph
	) throws
	{
		let image = PinnedSummaryIcons.image(
			glyph,
			size: 48
		)
		let bitmap = try rasterize(image)
		#expect(image.isTemplate == !glyph.isAgent)
		#expect(alpha(
			bitmap,
			x: 0,
			y: 0
		) == 0)
		#expect(alpha(
			bitmap,
			x: 47,
			y: 47
		) == 0)
		var opaquePixels = 0
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide where alpha(
				bitmap,
				x: x,
				y: y
			) > 0.5
			{
				opaquePixels += 1
			}
		}
		#expect(opaquePixels > 20)
		#expect(opaquePixels < bitmap.pixelsWide * bitmap.pixelsHigh)
	}

	@Test func linkedNodesHaveHollowCentersAndNoTriangleEdge() throws
	{
		let bitmap = try rasterize(PinnedSummaryIcons.image(
			.viewAll,
			size: 48
		))
		for coordinate in [10, 24, 38]
		{
			#expect(alpha(
				bitmap,
				x: coordinate,
				y: 47 - coordinate
			) < 0.1)
		}
		#expect(alpha(
			bitmap,
			x: 10,
			y: 9
		) < 0.1)
		#expect(alpha(
			bitmap,
			x: 38,
			y: 37
		) < 0.1)
	}

	@Test func toggleUsesTwoHollowBulletsBesideTwoSeparateLines() throws
	{
		let bitmap = try rasterize(PinnedSummaryIcons.image(
			.toggle,
			size: 48
		))
		#expect(alpha(
			bitmap,
			x: 10,
			y: 12
		) < 0.1)
		#expect(alpha(
			bitmap,
			x: 10,
			y: 34
		) < 0.1)
		#expect(alpha(
			bitmap,
			x: 34,
			y: 12
		) > 0.5)
		#expect(alpha(
			bitmap,
			x: 34,
			y: 34
		) > 0.5)
		#expect(alpha(
			bitmap,
			x: 34,
			y: 24
		) < 0.1)
	}

	@Test func agentArtworkKeepsDistinctColorsAndIndependentSizing() throws
	{
		let images = PinnedSummaryIcons.agentImages(size: 24)
		#expect(images.count == 4)
		#expect(images.allSatisfy
		{
			!$0.isTemplate
		})
		let centers = try images.map
		{
			try #require(rasterize($0).colorAt(
				x: 12,
				y: 12
			)?.usingColorSpace(.deviceRGB))
		}
		#expect(centers[0].redComponent > centers[0].greenComponent)
		#expect(centers[1].blueComponent > centers[1].greenComponent)
		#expect(centers[2].redComponent > centers[2].blueComponent)
		let green = try #require(rasterize(images[3]).colorAt(
			x: 13,
			y: 7
		)?.usingColorSpace(.deviceRGB))
		#expect(green.greenComponent > green.redComponent)
		images[0].size = NSSize(
			width: 40,
			height: 40
		)
		#expect(PinnedSummaryIcons.agentImages(size: 24)[0].size.width == 24)
	}

	private func rasterize(_ image: NSImage) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(image.size.width),
			pixelsHigh: Int(image.size.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
		image.draw(in: NSRect(
			origin: .zero,
			size: image.size
		))
		NSGraphicsContext.restoreGraphicsState()
		return bitmap
	}

	private func alpha(
		_ bitmap: NSBitmapImageRep,
		x: Int,
		y: Int
	) -> CGFloat
	{
		bitmap.colorAt(
			x: x,
			y: y
		)?.alphaComponent ?? 0
	}
}
