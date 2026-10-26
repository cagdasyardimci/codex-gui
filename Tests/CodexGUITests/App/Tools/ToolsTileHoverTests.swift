import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ToolsTileHoverTests
{
	@Test func sharedHoverTrackingKeepsTilePressAndActionBehavior() throws
	{
		_ = NSApplication.shared
		let controller = ToolsTabViewController()
		let tile = try #require(buttons(in: controller.view).first
		{
			$0.title == "Files"
		})
		tile.frame = NSRect(
			x: 0,
			y: 0,
			width: 160,
			height: 44
		)
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		var openedFiles = 0
		controller.onOpenFiles =
		{
			openedFiles += 1
		}

		let idle = try background(tile)
		tile.highlight(true)
		#expect(try background(tile) == idle)
		tile.highlight(false)
		tile.mouseEntered(with: event)
		#expect(try background(tile) != idle)
		tile.isEnabled = false
		#expect(try background(tile) == idle)
		tile.isEnabled = true
		tile.mouseExited(with: event)
		#expect(try background(tile) == idle)
		try #require(tile.dispatchConfiguredAction())
		#expect(openedFiles == 1)

		let standard = DesktopHoverButton(frame: tile.frame)
		let standardIdle = try background(standard)
		standard.highlight(true)
		#expect(try background(standard) != standardIdle)
	}

	private func buttons(in view: NSView) -> [DesktopHoverButton]
	{
		(view as? DesktopHoverButton).map
		{
			[$0]
		} ?? view.subviews.flatMap(buttons)
	}

	private func background(_ button: DesktopHoverButton) throws -> Data
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 160,
			pixelsHigh: 44,
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
		button.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			// The translucent dark fills require the real canvas to retain state contrast.
			AppKitColorTokens.toolsCanvas.setFill()
			button.bounds.fill()
			button.drawBackground()
		}
		return try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
	}
}
