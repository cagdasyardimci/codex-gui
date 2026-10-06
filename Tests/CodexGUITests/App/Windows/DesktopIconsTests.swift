import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct DesktopIconsTests
{
	@Test func independentControlImagesDoNotMutateThePackageCache()
	{
		let small = DesktopIcons.image(
			.folder,
			size: 13,
			accessibilityDescription: "Project"
		)
		let large = DesktopIcons.image(
			.folder,
			size: 28
		)
		large.isTemplate = false

		#expect(small !== large)
		#expect(small.size == NSSize(
			width: 13,
			height: 13
		))
		#expect(small.isTemplate)
		#expect(small.accessibilityDescription == "Project")
		let next = DesktopIcons.image(.folder)
		#expect(next.size == NSSize(
			width: 16,
			height: 16
		))
		#expect(next.isTemplate)
		#expect(next.accessibilityDescription == nil)
	}

	@Test(arguments: [
		DesktopIcon.search,
		.folderOpen,
		.chatCompose,
		.shieldCheck,
		.handRaised,
		.warning,
		.triangleExclamationErrorWarning,
		.stopCircleFilled,
		.pinFilled,
		.keyboardShortcut,
		.bolt,
		.chevronDown,
	])
	func bundledArtworkDecodesAndProducesVisiblePixels(_ icon: DesktopIcon) throws
	{
		_ = NSApplication.shared
		let image = DesktopIcons.image(
			icon,
			size: 24
		)
		let data = try #require(image.tiffRepresentation)
		let bitmap = try #require(NSBitmapImageRep(data: data))
		#expect(bitmap.pixelsWide > 0)
		#expect(bitmap.pixelsHigh > 0)
		#expect(try visibleColors(bitmap).count > 0)
	}

	@Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
	func customDrawingPreservesTintAndTransparentBackground(_ appearance: NSAppearance.Name) throws
	{
		_ = NSApplication.shared
		let image = NSImage(size: NSSize(
			width: 24,
			height: 24
		))
		let effectiveAppearance = try #require(NSAppearance(named: appearance))
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			image.lockFocus()
			DesktopIcons.draw(
				.bolt,
				in: NSRect(
					x: 0,
					y: 0,
					width: 24,
					height: 24
				),
				tint: .systemRed
			)
			image.unlockFocus()
		}
		let data = try #require(image.tiffRepresentation)
		let bitmap = try #require(NSBitmapImageRep(data: data))
		let colors = try visibleColors(bitmap)
		#expect(!colors.isEmpty)
		#expect(colors.count < bitmap.pixelsWide * bitmap.pixelsHigh)
		#expect(colors.allSatisfy
		{
			$0.redComponent > $0.greenComponent + 0.2
		})
	}

	private func visibleColors(_ bitmap: NSBitmapImageRep) throws -> [NSColor]
	{
		var colors: [NSColor] = []
		for y in 0 ..< bitmap.pixelsHigh
		{
			for x in 0 ..< bitmap.pixelsWide
			{
				let color = try #require(bitmap.colorAt(
					x: x,
					y: y
				)?.usingColorSpace(.deviceRGB))
				if color.alphaComponent > 0.5
				{
					colors.append(color)
				}
			}
		}
		return colors
	}
}
