import AppKit
import CoreText
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SidebarTypographyTests
{
	@Test func sidebarAntialiasingReducesStrokeCoverageWithoutChangingFont() throws
	{
		_ = NSApplication.shared
		let ordinary = NSTextField(labelWithString: "Use Chrome DevTools MCP")
		let sidebar = SidebarTextField(labelWithString: ordinary.stringValue)
		for field in [ordinary, sidebar]
		{
			field.frame = NSRect(
				x: 0,
				y: 0,
				width: 240,
				height: 30
			)
			field.font = AppKitFontResolver.interfaceFont(ofSize: 14)
			field.textColor = .black
		}
		#expect(ordinary.font == sidebar.font)
		#expect(ordinary.intrinsicContentSize == sidebar.intrinsicContentSize)
		let ordinaryCoverage = try darkPixelCount(of: ordinary)
		let sidebarCoverage = try darkPixelCount(of: sidebar)
		#expect(sidebarCoverage > 0)
		#expect(sidebarCoverage < ordinaryCoverage)
	}

	private func darkPixelCount(of field: NSTextField) throws -> Int
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 480,
			pixelsHigh: 60,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		context.cgContext.scaleBy(
			x: 2,
			y: 2
		)
		context.cgContext.setShouldSmoothFonts(true)
		NSColor.white.setFill()
		field.bounds.fill()
		field.draw(field.bounds)
		var count = 0
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide
			{
				let color = try #require(bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.deviceRGB))
				if (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.78
				{
					count += 1
				}
			}
		}
		return count
	}
}
