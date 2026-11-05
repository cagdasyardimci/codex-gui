import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ViewerToolbarButtonTests
{
	@Test func sharedHoverPaintsEnabledUnselectedActions() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 100,
					height: 100
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			let icon = try #require(FileViewerIcons.image(.fileSearch))
			let button = ViewerToolbarButton.icon(
				"Search",
				image: icon,
				target: nil,
				action: nil
			)
			button.frame = NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			)
			window.contentView?.addSubview(button)
			window.contentView?.layoutSubtreeIfNeeded()
			let normal = try pixels(button)
			button.setHovered(true)
			#expect(try pixels(button) != normal)
			button.setHovered(false)
			button.isEnabled = false
			let disabled = try pixels(button)
			button.setHovered(true)
			#expect(try pixels(button) == disabled)
			button.setHovered(false)
			button.isEnabled = true
			button.showsSelection = true
			button.state = .on
			let selected = try pixels(button)
			button.setHovered(true)
			#expect(try pixels(button) != selected)
		}
	}

	private func pixels(_ view: NSView) throws -> Data
	{
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		let bytes = try #require(bitmap.bitmapData)
		let count = bitmap.bytesPerRow * bitmap.pixelsHigh
		bytes.initialize(
			repeating: 0,
			count: count
		)
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		return Data(
			bytes: bytes,
			count: count
		)
	}
}
