import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct WebLinkFaviconAttachmentTests
{
	@Test func darkMonochromeIconRemainsVisibleAcrossAppearanceChanges() throws
	{
		let source = icon(color: NSColor(
			srgbRed: 23.0 / 255,
			green: 21.0 / 255,
			blue: 21.0 / 255,
			alpha: 1
		))
		let fitted = WebLinkFaviconAttachment.fit(source)
		#expect(fitted.size == NSSize(
			width: 18,
			height: 14
		))
		let light = try centerColor(
			of: fitted,
			appearance: .aqua
		)
		let dark = try centerColor(
			of: fitted,
			appearance: .darkAqua
		)
		let lightAgain = try centerColor(
			of: fitted,
			appearance: .aqua
		)
		#expect(light.redComponent < 0.2)
		#expect(dark.redComponent > 0.8)
		#expect(lightAgain.redComponent < 0.2)
	}

	@Test func coloredIconKeepsItsColorInDarkAppearance() throws
	{
		let fitted = WebLinkFaviconAttachment.fit(icon(color: .orange))
		let dark = try centerColor(
			of: fitted,
			appearance: .darkAqua
		)
		#expect(dark.redComponent > 0.8)
		#expect(dark.greenComponent < 0.7)
		#expect(dark.blueComponent < 0.3)
	}

	private func icon(color: NSColor) -> NSImage
	{
		NSImage(
			size: NSSize(
				width: 32,
				height: 32
			),
			flipped: false
		)
		{
			_ in
			color.setFill()
			NSBezierPath(ovalIn: NSRect(
				x: 2,
				y: 2,
				width: 28,
				height: 28
			)).fill()
			return true
		}
	}

	private func centerColor(
		of image: NSImage,
		appearance name: NSAppearance.Name
	) throws -> NSColor
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 18,
			pixelsHigh: 14,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		let appearance = try #require(NSAppearance(named: name))
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		appearance.performAsCurrentDrawingAppearance
		{
			NSColor.clear.setFill()
			NSRect(
				x: 0,
				y: 0,
				width: 18,
				height: 14
			).fill()
			image.draw(in: NSRect(
				x: 0,
				y: 0,
				width: 18,
				height: 14
			))
		}
		NSGraphicsContext.restoreGraphicsState()
		return try #require(bitmap.colorAt(
			x: 7,
			y: 7
		)?.usingColorSpace(.deviceRGB))
	}
}
