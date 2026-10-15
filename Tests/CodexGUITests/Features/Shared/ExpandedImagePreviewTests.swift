import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized,
	.testTiming
) @MainActor
struct ExpandedImagePreviewTests
{
	@Test func fitsWithoutCroppingAndKeepsZoomAcrossResizeAndAppearance() async throws
	{
		let window = makeWindow()
		let preview = ExpandedImagePreview()
		defer
		{
			preview.dismiss(); window.close()
		}
		preview.present(
			path: try imagePath(),
			name: "Wide image",
			in: window
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		#expect(controller.originalPixelSize == NSSize(
			width: 1600,
			height: 900
		))
		#expect(abs(controller.imageView.frame.width - 1600) < 0.01)
		let viewport = controller.scrollView.contentSize
		let fit = min(
			1,
			min(
				viewport.width / (1600),
				viewport.height / (900)
			)
		)
		#expect(abs(controller.scrollView.magnification - fit) < 0.01)
		#expect(controller.scrollView.allowsMagnification)
		controller.showActualSize()
		#expect(controller.displayedZoomPercentage == 100)
		controller.setZoom(2)
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: appearance)
			window.setContentSize(NSSize(
				width: 600,
				height: 400
			))
			window.contentView?.layoutSubtreeIfNeeded()
			#expect(controller.displayedZoomPercentage == 200)
			#expect(preview.controller === controller)
			#expect(controller.view.bounds == window.contentView?.bounds)
		}
		controller.fitImage()
		#expect(controller.scrollView.magnification < 1)
		#expect(controller.closeButton.accessibilityLabel() == "Close image")
		#expect(controller.zoomButton.accessibilityLabel() == "Image zoom")
		#expect(controller.zoomButton.itemTitles.contains("Fit"))
		#expect(controller.zoomButton.itemTitles.contains("Actual Size"))
		for (title, percentage) in [("25%", 25),
									("50%", 50),
									("100%", 100),
									("200%", 200),
									("400%", 400),
									("Actual Size", 100)]
		{
			let item = try #require(controller.zoomButton.itemArray.dropFirst().first
			{
				$0.title == title
			})
			controller.zoomButton.select(item)
			#expect(NSApplication.shared.sendAction(
				try #require(controller.zoomButton.action),
				to: controller.zoomButton.target,
				from: controller.zoomButton
			))
			#expect(controller.displayedZoomPercentage == percentage)
		}
		controller.zoomButton.selectItem(withTitle: "Fit")
		#expect(NSApplication.shared.sendAction(
			try #require(controller.zoomButton.action),
			to: controller.zoomButton.target,
			from: controller.zoomButton
		))
		#expect(controller.scrollView.magnification < 1)
	}

	@Test func referenceWidthsFitToTheSameCenteredViewport() async throws
	{
		let window = makeWindow()
		window.setContentSize(NSSize(
			width: 1493,
			height: 876
		))
		let preview = ExpandedImagePreview()
		defer
		{
			preview.dismiss()
			window.close()
		}
		preview.present(
			path: try imagePath(),
			name: "Geometry fixture",
			in: window
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		let image = try #require(controller.imageView.image?.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		))
		var previousHeight: CGFloat = .greatestFiniteMagnitude
		for (width, percentage) in [(2284, 59), (2570, 53), (2986, 45)]
		{
			let size = NSSize(
				width: width,
				height: 1228
			)
			controller.display(SourceThumbnailLoader.Thumbnail(
				image: image,
				originalPixelSize: size
			))
			controller.fitImage()
			#expect(controller.displayedZoomPercentage == percentage)
			#expect(controller.imageView.frame.size == size)
			let imageRect = controller.imageView.convert(
				controller.imageView.bounds,
				to: controller.view
			)
			let viewport = controller.scrollView.frame
			#expect(abs(imageRect.width - viewport.width) < 1)
			#expect(abs(imageRect.midX - viewport.midX) < 1)
			#expect(abs(imageRect.midY - viewport.midY) < 1)
			#expect(abs(imageRect.height / imageRect.width - 1228 / CGFloat(width)) < 0.001)
			#expect(imageRect.height < previousHeight)
			#expect(imageRect.minY >= viewport.minY - 1)
			#expect(imageRect.maxY <= viewport.maxY + 1)
			previousHeight = imageRect.height
		}
		var demandedPixels = 0
		controller.onResolutionDemand =
		{
			demandedPixels = $0
		}
		controller.showActualSize()
		#expect(controller.displayedZoomPercentage == 100)
		#expect(demandedPixels == Int(ceil(2986 * window.backingScaleFactor)))
	}

	@Test func tallReferencesShareHeightAndRefitWhenWidthBecomesTheLimit() async throws
	{
		let window = makeWindow()
		window.setContentSize(NSSize(
			width: 1493,
			height: 892
		))
		let preview = ExpandedImagePreview()
		defer
		{
			preview.dismiss()
			window.close()
		}
		preview.present(
			path: try imagePath(),
			name: "Tall geometry fixture",
			in: window
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		let image = try #require(controller.imageView.image?.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		))
		var previousWidth: CGFloat = 0
		for width in [600, 800, 1000]
		{
			controller.display(SourceThumbnailLoader.Thumbnail(
				image: image,
				originalPixelSize: NSSize(
					width: width,
					height: 1228
				)
			))
			controller.fitImage()
			let imageRect = controller.imageView.convert(
				controller.imageView.bounds,
				to: controller.view
			)
			let viewport = controller.scrollView.frame
			#expect(controller.displayedZoomPercentage == 61)
			#expect(abs(imageRect.height - viewport.height) < 1)
			#expect(abs(imageRect.midX - viewport.midX) < 1)
			#expect(abs(imageRect.midY - viewport.midY) < 1)
			#expect(abs(imageRect.width / imageRect.height - CGFloat(width) / 1228) < 0.001)
			#expect(imageRect.width > previousWidth)
			#expect(imageRect.minX >= viewport.minX - 1)
			#expect(imageRect.maxX <= viewport.maxX + 1)
			previousWidth = imageRect.width
		}
		// Resize the existing fitted viewer: width now limits the same tall image.
		window.setContentSize(NSSize(
			width: 500,
			height: 892
		))
		window.contentView?.layoutSubtreeIfNeeded()
		let narrowedImage = controller.imageView.convert(
			controller.imageView.bounds,
			to: controller.view
		)
		let narrowedViewport = controller.scrollView.frame
		#expect(controller.displayedZoomPercentage == 36)
		#expect(abs(narrowedImage.width - narrowedViewport.width) < 1)
		#expect(narrowedImage.height < narrowedViewport.height)
		#expect(abs(narrowedImage.midX - narrowedViewport.midX) < 1)
		#expect(abs(narrowedImage.midY - narrowedViewport.midY) < 1)
		window.setContentSize(NSSize(
			width: 1493,
			height: 892
		))
		window.contentView?.layoutSubtreeIfNeeded()
		#expect(controller.displayedZoomPercentage == 61)
	}

	// Native key routing and focus restoration need exclusive application interaction.
	@Test func closeAndEscapeRestoreFocusWithoutLeavingAnOverlay() async throws
	{
		let timing = TestTiming.begin("test.body")
		defer
		{
			timing.end()
		}
		// Encode independent fixture data before reserving native focus and event state.
		let firstPath = try imagePath()
		let secondPath = try imagePath()
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let window = makeWindow()
			let focus = NSTextView(frame: NSRect(
				x: 20,
				y: 20,
				width: 200,
				height: 80
			))
			try #require(window.contentView).addSubview(focus)
			let preview = ExpandedImagePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			#expect(window.makeFirstResponder(focus))
			preview.present(
				path: firstPath,
				name: "Image",
				in: window
			)
			await preview.waitForPresentation()
			let first = try #require(preview.controller)
			#expect(window.firstResponder === first.view)
			let closeAction = TestTiming.begin(
				"image.action",
				detail: "close"
			)
			// Route this owned control's action; the next presentation retains native Escape input.
			try #require(first.closeButton.dispatchConfiguredAction())
			closeAction.end()
			#expect(preview.controller == nil)
			#expect(first.view.superview == nil)
			#expect(window.firstResponder === focus)
			preview.present(
				path: secondPath,
				name: "Image",
				in: window
			)
			await preview.waitForPresentation()
			let second = try #require(preview.controller)
			#expect(window.makeFirstResponder(second.closeButton))
			window.sendEvent(try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "\u{1b}",
				charactersIgnoringModifiers: "\u{1b}",
				isARepeat: false,
				keyCode: 53
			)))
			#expect(preview.controller == nil)
			#expect(second.view.superview == nil)
			#expect(window.firstResponder === focus)
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func replacementCancellationAndWindowCloseRejectEarlierLoads() async throws
	{
		try await withControlledImageLoader
		{
			loader in
			let firstImage = try thumbnail(
				width: 40,
				height: 20
			)
			let secondImage = try thumbnail(
				width: 20,
				height: 40
			)
			let window = makeWindow()
			let first = loader.makePreview()
			let second = loader.makePreview()
			defer
			{
				first.dismiss(); second.dismiss(); window.close()
			}
			var requests = loader.started.makeAsyncIterator()
			first.present(
				path: "first.png",
				name: "First",
				in: window
			)
			let old = try #require(first.controller)
			let firstTask = try loader.captureTask(from: first)
			let firstRequest = try #require(await requests.next())
			#expect(firstRequest.path == "first.png")
			#expect(firstRequest.maximumPixelSize == 2048)

			second.present(
				path: "second.png",
				name: "Second",
				in: window
			)
			let secondTask = try loader.captureTask(from: second)
			let secondRequest = try #require(await requests.next())
			#expect(secondRequest.path == "second.png")
			#expect(firstTask.isCancelled)
			#expect(first.controller == nil)
			#expect(old.view.superview == nil)
			let current = try #require(second.controller)
			try loader.complete(
				secondRequest,
				with: secondImage
			)
			await secondTask.value
			let retainedImage = try #require(current.imageView.image)
			#expect(current.originalPixelSize == NSSize(
				width: 20,
				height: 40
			))

			// Deliver the obsolete response after the new owner's successful presentation.
			try loader.complete(
				firstRequest,
				with: firstImage
			)
			await firstTask.value
			#expect(first.controller == nil)
			#expect(old.imageView.image == nil)
			#expect(old.view.superview == nil)
			#expect(second.controller === current)
			#expect(current.imageView.image === retainedImage)

			second.present(
				path: "closing.png",
				name: "Closing",
				in: window
			)
			let closing = try #require(second.controller)
			let closingTask = try loader.captureTask(from: second)
			let closingRequest = try #require(await requests.next())
			#expect(closingRequest.path == "closing.png")
			#expect(closing.imageView.image == nil)
			window.close()
			#expect(closingTask.isCancelled)
			#expect(second.controller == nil)
			#expect(closing.view.superview == nil)
			try loader.complete(
				closingRequest,
				with: firstImage
			)
			await closingTask.value
			#expect(second.controller == nil)
			#expect(closing.imageView.image == nil)
			#expect(closing.originalPixelSize == .zero)
			#expect(closing.view.superview == nil)
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func sameOwnerReplacementRejectsAnEarlierImageAfterTheNewImageLoads() async throws
	{
		try await withControlledImageLoader
		{
			loader in
			let earlierImage = try thumbnail(
				width: 40,
				height: 20
			)
			let replacementImage = try thumbnail(
				width: 20,
				height: 40
			)
			let window = makeWindow()
			let preview = loader.makePreview()
			defer
			{
				preview.dismiss(); window.close()
			}
			var requests = loader.started.makeAsyncIterator()
			preview.present(
				path: "earlier.png",
				name: "Earlier",
				in: window
			)
			let earlier = try #require(preview.controller)
			let earlierTask = try loader.captureTask(from: preview)
			let earlierRequest = try #require(await requests.next())
			#expect(earlierRequest.path == "earlier.png")

			preview.present(
				path: "replacement.png",
				name: "Replacement",
				in: window
			)
			let current = try #require(preview.controller)
			let currentTask = try loader.captureTask(from: preview)
			let currentRequest = try #require(await requests.next())
			#expect(currentRequest.path == "replacement.png")
			#expect(earlierTask.isCancelled)
			#expect(earlier.view.superview == nil)
			try loader.complete(
				currentRequest,
				with: replacementImage
			)
			await currentTask.value
			let retainedImage = try #require(current.imageView.image)
			#expect(current.originalPixelSize == NSSize(
				width: 20,
				height: 40
			))

			try loader.complete(
				earlierRequest,
				with: earlierImage
			)
			await earlierTask.value
			#expect(preview.controller === current)
			#expect(current.imageView.image === retainedImage)
			#expect(current.originalPixelSize == NSSize(
				width: 20,
				height: 40
			))
			#expect(earlier.imageView.image == nil)
			#expect(earlier.originalPixelSize == .zero)
			#expect(earlier.view.superview == nil)
		}
	}

	@Test func unreadableImagesKeepAnAccessibleClosePath() async throws
	{
		let window = makeWindow()
		let preview = ExpandedImagePreview()
		defer
		{
			preview.dismiss(); window.close()
		}
		preview.present(
			path: "/tmp/missing-image-\(UUID()).png",
			name: "Missing",
			in: window
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		#expect(controller.imageView.image == nil)
		#expect(!controller.zoomButton.isEnabled)
		#expect(controller.closeButton.isEnabled)
		try #require(controller.closeButton.dispatchConfiguredAction())
		#expect(preview.controller == nil)
	}

	@Test func backgroundAccessibilityIsRestoredOnDismissAndOwnerRelease() async throws
	{
		let window = makeWindow()
		let content = try #require(window.contentView)
		let button = NSButton(
			title: "Underlying action",
			target: nil,
			action: nil
		)
		let alreadyHidden = NSView()
		alreadyHidden.setAccessibilityHidden(true)
		content.addSubview(button)
		content.addSubview(alreadyHidden)
		var preview: ExpandedImagePreview? = ExpandedImagePreview()
		defer
		{
			preview?.dismiss()
			window.close()
		}
		preview?.present(
			path: try imagePath(),
			name: "Image",
			in: window
		)
		await preview?.waitForPresentation()
		#expect(button.isAccessibilityHidden())
		#expect(alreadyHidden.isAccessibilityHidden())
		let overlay = try #require(preview?.controller?.view)
		#expect(overlay.isAccessibilityElement())
		#expect(overlay.accessibilityRole() == .group)
		preview?.dismiss()
		#expect(!button.isAccessibilityHidden())
		#expect(alreadyHidden.isAccessibilityHidden())
		preview?.present(
			path: try imagePath(),
			name: "Image",
			in: window
		)
		await preview?.waitForPresentation()
		let releasedOverlay = try #require(preview?.controller?.view)
		preview = nil
		for _ in 0 ..< 100
		{
			if releasedOverlay.superview == nil
			{
				break
			}
			await Task.yield()
		}
		#expect(releasedOverlay.superview == nil)
		#expect(!button.isAccessibilityHidden())
		#expect(alreadyHidden.isAccessibilityHidden())
	}

	@Test func renderedViewportKeepsTheBackdropVisibleAndHeaderControlsRounded() async throws
	{
		let window = makeWindow()
		let background = ExpandedImageRenderingBackdrop(frame: NSRect(
			origin: .zero,
			size: NSSize(
				width: 900,
				height: 650
			)
		))
		window.contentView = background
		let preview = ExpandedImagePreview()
		defer
		{
			preview.dismiss()
			window.close()
		}
		preview.present(
			path: try imagePath(),
			name: "Rendering fixture",
			in: window
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		#expect(!controller.scrollView.drawsBackground)
		#expect(!controller.scrollView.contentView.drawsBackground)
		#expect(controller.zoomButton.bounds.size == NSSize(
			width: 64,
			height: 32
		))
		#expect(controller.closeButton.bounds.size == NSSize(
			width: 32,
			height: 32
		))
		let backdrop = try #require(controller.view.subviews.first as? NSVisualEffectView)
		#expect(backdrop.blendingMode == .withinWindow)
		#expect(backdrop.state == .active)
		#expect(backdrop.material == .fullScreenUI)
		#expect(backdrop.frame == controller.view.bounds)
		let dimming = try #require(controller.view.subviews.dropFirst().first)
		#expect(dimming.accessibilityIdentifier() == "expanded-image-dimming")
		#expect(dimming.frame == controller.view.bounds)
		#expect(backdrop.isAccessibilityHidden())
		#expect(dimming.isAccessibilityHidden())
		#expect(controller.scrollView.superview === controller.view)
		#expect(controller.zoomButton.superview === controller.view)
		#expect(controller.closeButton.superview === controller.view)
		// Bitmap caching does not capture WindowServer backdrop blur. Isolate the
		// dimming layer here to verify that the image viewport stays transparent.
		backdrop.isHidden = true
		let bitmap = try render(background)
		backdrop.isHidden = false
		let left = try #require(bitmap.colorAt(
			x: Int(CGFloat(bitmap.pixelsWide) * 0.2),
			y: bitmap.pixelsHigh / 2
		)?.usingColorSpace(.deviceRGB))
		let right = try #require(bitmap.colorAt(
			x: Int(CGFloat(bitmap.pixelsWide) * 0.8),
			y: bitmap.pixelsHigh / 2
		)?.usingColorSpace(.deviceRGB))
		#expect(left.redComponent > 0.15 && left.redComponent < 0.6)
		#expect(left.redComponent > left.blueComponent * 2)
		#expect(right.blueComponent > 0.15 && right.blueComponent < 0.6)
		#expect(right.blueComponent > right.redComponent * 2)
		if let output = ProcessInfo.processInfo.environment["CODEX_GUI_IMAGE_PREVIEW_CAPTURE"]
		{
			if let reference = ProcessInfo.processInfo
				.environment["CODEX_GUI_IMAGE_PREVIEW_REFERENCE"]
			{
				preview.present(
					path: reference,
					name: "Reference image",
					in: window
				)
				await preview.waitForPresentation()
			}
			let data = try #require(try render(background).representation(
				using: .png,
				properties: [:]
			))
			try data.write(to: URL(fileURLWithPath: output))
		}
	}

	private func withControlledImageLoader(
		_ body: @MainActor (ControlledImageLoader) async throws -> Void
	) async throws
	{
		let loader = ControlledImageLoader()
		do
		{
			try await body(loader)
		}
		catch
		{
			await loader.finish()
			throw error
		}
		await loader.finish()
	}

	private func thumbnail(
		width: Int,
		height: Int
	) throws -> SourceThumbnailLoader.Thumbnail
	{
		let context = try #require(CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		context.setFillColor(CGColor(
			red: CGFloat(width) / 100,
			green: CGFloat(height) / 100,
			blue: 0.25,
			alpha: 1
		))
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: width,
			height: height
		))
		return SourceThumbnailLoader.Thumbnail(
			image: try #require(context.makeImage()),
			originalPixelSize: CGSize(
				width: width,
				height: height
			)
		)
	}

	@MainActor
	private final class ControlledImageLoader
	{
		struct Request: Sendable
		{
			let id: Int
			let path: String
			let maximumPixelSize: Int
		}

		let started: AsyncStream<Request>
		private let starts: AsyncStream<Request>.Continuation
		private var pending: [Int: CheckedContinuation<SourceThumbnailLoader.Thumbnail?, Never>] =
			[:]
		private var tasks: [Task<Void, Never>] = []
		private var nextRequestID = 0
		private var finished = false

		init()
		{
			(started, starts) = AsyncStream<Request>.makeStream()
		}

		func makePreview() -> ExpandedImagePreview
		{
			ExpandedImagePreview
			{
				path, maximumPixelSize in
				await self.image(
					path: path,
					maximumPixelSize: maximumPixelSize
				)
			}
		}

		func captureTask(from preview: ExpandedImagePreview) throws -> Task<Void, Never>
		{
			let task = try #require(preview.presentationTask)
			tasks.append(task)
			return task
		}

		func complete(
			_ request: Request,
			with image: SourceThumbnailLoader.Thumbnail
		) throws
		{
			let pendingResponse = pending.removeValue(forKey: request.id)
			let continuation = try #require(pendingResponse)
			continuation.resume(returning: image)
		}

		func finish() async
		{
			finished = true
			let unfinished = Array(pending.values)
			pending.removeAll()
			starts.finish()
			for continuation in unfinished
			{
				continuation.resume(returning: nil)
			}
			for task in tasks
			{
				await task.value
			}
			tasks.removeAll()
		}

		private func image(
			path: String,
			maximumPixelSize: Int
		) async -> SourceThumbnailLoader
			.Thumbnail?
		{
			guard !finished
			else
			{
				return nil
			}
			let request = Request(
				id: nextRequestID,
				path: path,
				maximumPixelSize: maximumPixelSize
			)
			nextRequestID += 1
			// Intentionally return even after cancellation to exercise stale-response admission.
			return await withCheckedContinuation
			{
				pending[request.id] = $0
				starts.yield(request)
			}
		}
	}

	private func render(_ view: NSView) throws -> NSBitmapImageRep
	{
		view.layoutSubtreeIfNeeded()
		view.displayIfNeeded()
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		return bitmap
	}

	private func makeWindow() -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 650
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func imagePath() throws -> String
	{
		let timing = TestTiming.begin("image.encode")
		defer
		{
			timing.end()
		}
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 1600,
			pixelsHigh: 900,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		bitmap.bitmapData?.initialize(
			repeating: 0,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		return "data:image/png;base64," + data.base64EncodedString()
	}
}

@MainActor
private final class ExpandedImageRenderingBackdrop: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		NSColor(
			deviceRed: 0.8,
			green: 0.2,
			blue: 0.1,
			alpha: 1
		).setFill()
		NSRect(
			x: 0,
			y: 0,
			width: bounds.midX,
			height: bounds.height
		).fill()
		NSColor(
			deviceRed: 0.1,
			green: 0.2,
			blue: 0.8,
			alpha: 1
		).setFill()
		NSRect(
			x: bounds.midX,
			y: 0,
			width: bounds.width / 2,
			height: bounds.height
		).fill()
	}
}
