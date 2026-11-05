import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ExpandedImagePreviewTests
{
	@Test func imageCoversWindowChromeFitsItsViewportAndRestoresTheEditor() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let context = try #require(CGContext(
				data: nil,
				width: 1,
				height: 1,
				bitsPerComponent: 8,
				bytesPerRow: 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			))
			let thumbnail = SourceThumbnailLoader.Thumbnail(
				image: try #require(context.makeImage()),
				originalPixelSize: CGSize(
					width: 2478,
					height: 1530
				)
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1512,
					height: 841
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.setFrame(
				NSRect(
					x: 0,
					y: 0,
					width: 1512,
					height: 881
				),
				display: false
			)
			let field = NSTextField(frame: NSRect(
				x: 20,
				y: 20,
				width: 200,
				height: 28
			))
			field.stringValue = "Retained draft"
			window.contentView?.addSubview(field)
			#expect(window.makeFirstResponder(field))
			let editor = try #require(window.firstResponder as? NSTextView)
			let preview = ExpandedImagePreview(loadImage:
				{
					_, _ in thumbnail
				})
			defer
			{
				preview.dismiss(); window.close()
			}
			preview.present(
				path: "fixture.png",
				name: "Fixture",
				in: window
			)
			await preview.waitForPresentation()
			let controller = try #require(preview.controller)
			let overlay = try #require(controller.view.window)
			#expect(overlay.parent === window)
			#expect(overlay.frame == window.frame)
			let host = try #require(window.contentView?.superview ?? window.contentView)
			let blur = try #require(host.subviews.first
			{
				$0.accessibilityIdentifier() == "expanded-image-blur"
			})
			#expect(blur.isAccessibilityHidden())
			#expect(blur.hitTest(NSPoint(
				x: 5,
				y: 5
			)) == nil)
			#expect(blur.backgroundFilters.count == 1)
			#expect(blur.frame == host.bounds)
			#expect(controller.view.acceptsFirstResponder)
			#expect(!controller.view.canBecomeKeyView)
			for appearance in [NSAppearance.Name.darkAqua, .aqua, .darkAqua]
			{
				window.appearance = NSAppearance(named: appearance)
				#expect(overlay.effectiveAppearance
					.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			}
			controller.view.layoutSubtreeIfNeeded()
			#expect(controller.view.bounds.size == window.frame.size)
			#expect(controller.originalPixelSize == thumbnail.originalPixelSize)
			#expect(controller.scrollView.frame.height == 801)
			#expect(controller.displayedZoomPercentage == 52)
			let fittedFrame = controller.imageFrameView.frame.size
			let fitScale = controller.scrollView.magnification
			#expect(abs(fittedFrame.height * fitScale - 801) < 0.1)
			#expect(abs(fittedFrame.width * fitScale - 1296.06) < 0.1)
			controller.showActualSize()
			#expect(abs(controller.imageFrameView.frame.height - (1530 + 2 / fitScale)) < 0.01)
			controller.fitImage()
			#expect(controller.downloadButton.isEnabled)
			#expect(controller.zoomButton.nextKeyView === controller.downloadButton)
			#expect(controller.downloadButton.nextKeyView === controller.closeButton)
			let menu = try #require(controller.zoomButton.menu)
			#expect(menu.items.filter
			{
				!$0.isHidden && !$0.isSeparatorItem
			}.map(\.title) == [
				"25%",
				"50%",
				"100%",
				"150%",
				"200%",
				"Zoom to fit"
			])
			controller.zoomButton.selectItem(withTag: 150)
			#expect(controller.zoomButton.sendAction(
				controller.zoomButton.action,
				to: controller.zoomButton.target
			))
			#expect(controller.displayedZoomPercentage == 150)
			controller.fitImage()
			#expect(controller.displayedZoomPercentage == 52)
			window.setFrame(
				NSRect(
					x: 0,
					y: 0,
					width: 1200,
					height: 700
				),
				display: false
			)
			#expect(blur.frame == host.bounds)
			preview.dismiss()
			#expect(blur.superview == nil)
			#expect(overlay.parent == nil)
			#expect(window.firstResponder === editor)
			#expect(field.stringValue == "Retained draft")
		}
	}
	@Test func originalImageExportPreservesEncodedBytesAndRejectsUnsupportedSources() async throws
	{
		let image = NSImage(size: NSSize(
			width: 2,
			height: 2
		))
		image.lockFocus()
		NSColor.red.setFill()
		NSRect(
			x: 0,
			y: 0,
			width: 2,
			height: 2
		).fill()
		image.unlockFocus()
		let data = try #require(MarkdownDiagramExport.pngData(image))
		let inline = "data:image/png;base64," + data.base64EncodedString()
		let bytes = try #require(await SourceThumbnailLoader.originalData(path: inline))
		#expect(bytes == data)
		let file = try #require(ExpandedImagePreview.exportFile(
			data: bytes,
			name: "Image"
		))
		#expect(file.data == data)
		#expect(file.name == "Image.png")
		#expect(ExpandedImagePreview.exportFile(
			data: bytes,
			name: "image.jpg"
		)?
			.name == "image.png")
		#expect(ExpandedImagePreview.exportFile(
			data: bytes,
			name: "../original.png"
		)?
			.name == "original.png")
		let local = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString + ".png")
		defer
		{
			try? FileManager.default.removeItem(at: local)
		}
		try data.write(to: local)
		#expect(await SourceThumbnailLoader.originalData(path: local.path) == data)
		#expect(await SourceThumbnailLoader
			.originalData(path: "https://example.invalid/a.png") == nil)
		#expect(ExpandedImagePreview
			.exportFile(
				data: Data("not an image".utf8),
				name: "x.png"
			) == nil)
	}

}
