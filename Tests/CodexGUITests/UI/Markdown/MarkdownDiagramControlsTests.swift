import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct MarkdownDiagramControlsTests
{

	@Test func expandedDiagramUsesNaturalSizeAndRoutesZoomAndClose() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1000,
					height: 800
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.appearance = NSAppearance(named: .aqua)
			let preview = ExpandedImagePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			let svg = Data(
				("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"220\" height=\"500\">"
					+ "<rect width=\"220\" height=\"500\" fill=\"#5796ff\"/></svg>").utf8
			)
			let image = try #require(MarkdownSVGImage(
				data: svg,
				size: NSSize(
					width: 220,
					height: 500
				)
			))
			preview.present(
				path: "",
				name: "Diagram",
				in: window,
				preparedDiagram: image
			)
			let controller = try #require(preview.controller)
			let overlayWindow = try #require(controller.view.window)
			#expect(overlayWindow !== window)
			#expect(overlayWindow.parent === window)
			#expect(overlayWindow.frame == window.frame)
			#expect(overlayWindow.canBecomeKey)
			#expect(controller.view.bounds.size == window.frame.size)
			#expect(controller.view.bounds.height > (window.contentView?.bounds.height ?? 0))
			#expect(controller.backdropView.isHidden)
			#expect(controller.originalPixelSize == image.size)
			#expect(controller.displayedZoomPercentage == 100)
			let buttons = descendants(controller.view).compactMap
			{
				$0 as? NSButton
			}
			let plus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom in"
			})
			#expect(plus.sendAction(
				plus.action,
				to: plus.target
			))
			#expect(controller.displayedZoomPercentage == 110)
			let minus = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Zoom out"
			})
			#expect(minus.sendAction(
				minus.action,
				to: minus.target
			))
			#expect(controller.displayedZoomPercentage == 100)
			controller.setZoom(1.97)
			#expect(controller.displayedZoomPercentage == 197)
			#expect(controller.scrollView.allowsMagnification)
			let download = try #require(buttons.first
			{
				$0.accessibilityLabel() == "Download image"
			})
			#expect(download.frame.width == download.frame.height)
			controller.view.layoutSubtreeIfNeeded()
			let bounds = controller.view.bounds
			let close = controller.closeButton.frame
			#expect(close.size == NSSize(
				width: 40,
				height: 40
			))
			#expect(abs(bounds.maxX - close.maxX - 12) < 0.01)
			#expect(abs(bounds.maxY - close.maxY - 12) < 0.01)
			#expect(download.frame.size == NSSize(
				width: 40,
				height: 40
			))
			#expect(abs(bounds.maxX - download.frame.maxX - 60) < 0.01)
			#expect(abs(bounds.maxY - download.frame.maxY - 12) < 0.01)
			#expect(plus.frame.size == NSSize(
				width: 36,
				height: 36
			))
			#expect(minus.frame.size == NSSize(
				width: 36,
				height: 36
			))
			let zoomPill = try #require(plus.superview?.superview as? ExpandedImageZoomGroup)
			#expect(zoomPill.frame.size == NSSize(
				width: 152,
				height: 44
			))
			let canvasView = try #require(controller.scrollView.superview)
			let canvas = canvasView.frame
			#expect(abs(canvas.minX - bounds.minX - 32) < 0.01)
			#expect(abs(bounds.maxX - canvas.maxX - 32) < 0.01)
			#expect(abs(bounds.maxY - canvas.maxY - 48) < 0.01)
			#expect(abs(canvas.minY - bounds.minY - 96) < 0.01)
			#expect(canvasView.layer?.cornerRadius == 20)
			#expect(controller.scrollView.frame == canvasView.bounds.insetBy(
				dx: 16,
				dy: 16
			))
			#expect(controller.scrollView.layer?.masksToBounds == true)
			#expect(controller.imageView.image === image)
			#expect(image.representations.allSatisfy
			{
				!($0 is NSBitmapImageRep)
			})
			let exported = try #require(MarkdownDiagramExport.file(image))
			#expect(exported.data == svg)
			#expect(exported.contentType.identifier == "public.svg-image")
			#expect(exported.name == "diagram.svg")
			var resizedFrame = window.frame
			resizedFrame.size.width += 100
			resizedFrame.size.height += 80
			window.setFrame(
				resizedFrame,
				display: false
			)
			NotificationCenter.default.post(
				name: NSWindow.didResizeNotification,
				object: window
			)
			#expect(overlayWindow.frame == window.frame)
			#expect(controller.view.bounds.size == window.frame.size)
			#expect(controller.closeButton.sendAction(
				controller.closeButton.action,
				to: controller.closeButton.target
			))
			#expect(preview.controller == nil)
			#expect(overlayWindow.parent == nil)
			#expect(overlayWindow.isVisible == false)
			#expect(controller.view.window == nil)
		}
	}

	private func capture(
		_ view: NSView,
		name: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_DIAGRAM_CAPTURE_DIR"]
		else
		{
			return
		}
		view.layoutSubtreeIfNeeded()
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
