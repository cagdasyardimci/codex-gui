import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	.serialized,
	.testTiming
)
struct ConversationTerminalCopyButtonTests
{
	// Native event polling and transient panels share the application event/window state.
	@Test func retainedHoverRedrawsAfterWindowAppearanceChanges() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			// Appearance assertions require retained hover, independently of the physical pointer.
			let window = TranscriptPointerTestWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 100,
					height: 100
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.pointerLocation = NSPoint(
				x: 50,
				y: 50
			)
			let button = ConversationTerminalCopyButton(frame: NSRect(
				x: 38,
				y: 38,
				width: 24,
				height: 24
			))
			button.title = ""
			button.isBordered = false
			button.setAccessibilityLabel("Copy output")
			try #require(window.contentView).addSubview(button)
			defer
			{
				button.resetHover()
				window.close()
			}
			window.appearance = try #require(NSAppearance(named: .darkAqua))
			window.orderFront(nil)
			button.updateTrackingAreas()
			#expect(button.isHovered)
			let responder = window.firstResponder
			let originalFrame = button.frame
			var lightSample: CGFloat?
			for name in [NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua]
			{
				button.needsDisplay = false
				window.appearance = try #require(NSAppearance(named: name))
				#expect(button.needsDisplay)
				#expect(button.isHovered)
				#expect(button.isGlyphVisible)
				#expect(button.frame == originalFrame)
				#expect(window.firstResponder === responder)
				#expect(button.accessibilityLabel() == "Copy output")
				let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
				button.cacheDisplay(
					in: button.bounds,
					to: bitmap
				)
				let color = try #require(bitmap.colorAt(
					x: bitmap.pixelsWide / 2,
					y: 3
				))
				let sample = try #require(color.usingColorSpace(.deviceRGB)).redComponent
				if name == .aqua
				{
					lightSample = sample
				}
				else
				{
					#expect(sample > (try #require(lightSample)) + 0.5)
				}
			}
		}
	}
}
