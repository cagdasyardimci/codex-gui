import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ImageCommentToolbarTests
{
	@Test(.appKitIsolation) func fullLabelsFitInBothAppearancesAndToolbarFollowsImage() throws
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 800,
				height: 600
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		defer
		{
			window.close()
		}
		let host = try #require(window.contentView)
		let toolbar = ImageCommentToolbar()
		host.addSubview(toolbar)
		let image = NSRect(
			x: 100,
			y: 200,
			width: 600,
			height: 300
		)
		var surfaceColors: [NSColor] = []
		for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
		{
			window.appearance = NSAppearance(named: appearance)
			toolbar.render(commenting: false)
			toolbar.place(
				below: image,
				in: host.bounds
			)
			#expect(toolbar.frame.height == 40)
			#expect(abs(toolbar.frame.midX - image.midX) < 0.01)
			#expect(abs(toolbar.frame.maxY - (image.minY - 16)) < 0.01)
			let natural = (toolbar.commentButton.title as NSString).size(withAttributes: [
				.font: try #require(toolbar.commentButton.font)
			])
			let titleRect = toolbar.commentButton.contentLayout(in: toolbar.commentButton.bounds)
				.title
			#expect(titleRect.width >= natural.width)
			#expect(abs(titleRect.height - natural.height) < 0.01)
			#expect(abs(titleRect.midY - toolbar.commentButton.bounds.midY) < 0.01)
			#expect(toolbar.moveHandle.frame.width == 24)
			toolbar.effectiveAppearance.performAsCurrentDrawingAppearance
			{
				if let color = AppKitColorTokens.imageAnnotationSurface.usingColorSpace(.sRGB)
				{
					surfaceColors.append(color)
				}
			}
			// Retain rendered native evidence for reviewing glyph clipping and the inverse surface.
			let capture = try #require(toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds))
			toolbar.cacheDisplay(
				in: toolbar.bounds,
				to: capture
			)
			let directory = FileManager.default.temporaryDirectory
				.appendingPathComponent("codex-gui-image-comment-review")
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
			try #require(capture.representation(
				using: .png,
				properties: [:]
			)).write(to: directory.appendingPathComponent("toolbar-\(name).png"))
			toolbar.render(
				commenting: true,
				count: 12
			)
			toolbar.place(
				below: image,
				in: host.bounds
			)
			let saveNatural = (toolbar.saveButton.title as NSString).size(withAttributes: [
				.font: try #require(toolbar.saveButton.font)
			])
			#expect(toolbar.saveButton.contentLayout(in: toolbar.saveButton.bounds).title
				.width >= saveNatural.width)
			#expect(toolbar.cancelButton.accessibilityLabel() == "Cancel image comments")
		}
		#expect(surfaceColors.count == 2)
		#expect(surfaceColors.first == surfaceColors.last)
		#expect(surfaceColors.first?.redComponent ?? 1 < 0.3)
	}

	@Test(.appKitIsolation) func movementStaysInViewportAndResetRestoresImagePlacement() throws
	{
		let toolbar = ImageCommentToolbar()
		let viewport = NSRect(
			x: 0,
			y: 0,
			width: 800,
			height: 600
		)
		let image = NSRect(
			x: 100,
			y: 200,
			width: 600,
			height: 300
		)
		toolbar.place(
			below: .zero,
			in: .zero
		)
		toolbar.place(
			below: image,
			in: viewport
		)
		#expect(toolbar.frame.midX == viewport.midX)
		let initial = toolbar.frame
		toolbar.onPlacementChange =
		{
			toolbar.place(
				below: image,
				in: viewport
			)
		}
		defer
		{
			toolbar.onPlacementChange = nil
		}
		toolbar.move(by: NSSize(
			width: 10000,
			height: -10000
		))
		#expect(viewport.contains(toolbar.frame))
		#expect(toolbar.frame.minY == 8)
		toolbar.moveHandle.onReset?()
		#expect(toolbar.frame == initial)
	}
}
