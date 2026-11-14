import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ImageCommentCanvasTests
{
	@Test(
		.appKitIsolation,
		arguments: [nil, UInt16(36), UInt16(76)]
	)
	func savingToTheDraftClosesViewerAndRestoresPinsOnReopen(returnKey: UInt16?) async throws
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
		let preview = ExpandedImagePreview(loadImage:
			{
				_, _ in nil
			})
		defer
		{
			preview.dismiss(); window.close()
		}
		let initial = ImageAnnotation(
			x: 0.8,
			y: 0.7,
			text: "Original"
		)
		var saved: [ImageAnnotation] = []
		preview.present(
			path: "/unused",
			name: "image.png",
			in: window,
			annotations: [initial],
			onSaveAnnotations:
			{
				saved = $0
			}
		)
		await preview.waitForPresentation()
		let controller = try #require(preview.controller)
		let context = try #require(CGContext(
			data: nil,
			width: 1,
			height: 1,
			bitsPerComponent: 8,
			bytesPerRow: 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast
				.rawValue
		))
		controller.display(SourceThumbnailLoader.Thumbnail(
			image: try #require(context.makeImage()),
			originalPixelSize: NSSize(
				width: 600,
				height: 400
			)
		))
		controller.view.layoutSubtreeIfNeeded()
		let canvas = try #require(controller.commentCanvas)
		let toolbar = try #require(controller.view.subviews
			.compactMap
			{
				$0 as? ImageCommentToolbar
			}.first)
		#expect(toolbar.commentButton.dispatchConfiguredAction())
		let rect = canvas.imageRect
		canvas.addComment(at: NSPoint(
			x: rect.midX,
			y: rect.midY
		))
		let editor = try #require(canvas.subviews.compactMap
		{
			$0 as? ImageCommentEditor
		}.first)
		try #require(editor.inputField).stringValue = "Center"
		editor.textDidChange(Notification(name: NSText.didChangeNotification))
		if let returnKey
		{
			#expect(canvas.commitEditing())
			let event = try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				characters: "\r",
				charactersIgnoringModifiers: "\r",
				isARepeat: false,
				keyCode: returnKey
			))
			canvas.keyDown(with: event)
		}
		else
		{
			#expect(toolbar.saveButton.dispatchConfiguredAction())
		}
		#expect(saved.map(\.text) == ["Original", "Center"])
		#expect(saved.last?.x == 0.5)
		#expect(saved.last?.y == 0.5)
		#expect(preview.controller == nil)
		#expect(window.childWindows?.isEmpty != false)
		preview.present(
			path: "/unused",
			name: "image.png",
			in: window,
			annotations: saved,
			onSaveAnnotations:
			{
				saved = $0
			}
		)
		#expect(preview.controller?.commentCanvas?.annotations == saved)
	}

	@Test(.appKitIsolation) func pinsUseTopLeftCoordinatesAndKeepTheirSizeThroughZoom() throws
	{
		let canvas = ImageCommentCanvas(annotations: [])
		canvas.frame = NSRect(
			x: 0,
			y: 0,
			width: 800,
			height: 600
		)
		canvas.imageRect = NSRect(
			x: 100,
			y: 100,
			width: 400,
			height: 300
		)
		canvas.beginCommenting()
		canvas.addComment(at: NSPoint(
			x: 200,
			y: 325
		))
		let editor = try #require(canvas.subviews.compactMap
		{
			$0 as? ImageCommentEditor
		}.first)
		try #require(editor.inputField).stringValue = "Upper left quadrant"
		editor.textDidChange(Notification(name: NSText.didChangeNotification))
		#expect(editor.save())
		let annotation = try #require(canvas.annotations.first)
		#expect(annotation.x == 0.25)
		#expect(annotation.y == 0.25)
		canvas.layoutSubtreeIfNeeded()
		let placedPin = try #require(canvas.subviews.compactMap
		{
			$0 as? DesktopActionButton
		}
		.first)
		#expect(placedPin.frame.origin == NSPoint(
			x: 200,
			y: 325
		))
		canvas.imageRect = NSRect(
			x: -100,
			y: -200,
			width: 800,
			height: 600
		)
		canvas.layoutSubtreeIfNeeded()
		let pin = try #require(canvas.subviews.compactMap
		{
			$0 as? DesktopActionButton
		}.first)
		#expect(pin.frame.size == NSSize(
			width: 30,
			height: 30
		))
		#expect(pin.frame.minX == 100)
		#expect(pin.frame.minY == 250)
		#expect(canvas.annotations == [annotation])
		canvas.cancelCommenting()
		#expect(canvas.annotations.isEmpty)
	}

	@Test(.appKitIsolation) func editingCanBeCancelledSavedAndDeletedWithoutSending() throws
	{
		let annotation = ImageAnnotation(
			x: 0.5,
			y: 0.5,
			text: "Original"
		)
		let canvas = ImageCommentCanvas(annotations: [annotation])
		canvas.frame = NSRect(
			x: 0,
			y: 0,
			width: 400,
			height: 300
		)
		canvas.imageRect = canvas.bounds
		canvas.beginCommenting()
		func pin() throws -> DesktopActionButton
		{
			try #require(canvas.subviews.compactMap
			{
				$0 as? DesktopActionButton
			}.first)
		}
		func editor() throws -> ImageCommentEditor
		{
			try #require(canvas.subviews.compactMap
			{
				$0 as? ImageCommentEditor
			}.first)
		}
		try pin().dispatchConfiguredAction()
		try editor().textView.string = "Discard"
		#expect(canvas.cancelEditing())
		#expect(canvas.annotations == [annotation])
		try pin().dispatchConfiguredAction()
		let edit = try editor()
		edit.textView.string = "Saved"
		edit.textDidChange(Notification(name: NSText.didChangeNotification))
		#expect(edit.saveButton.dispatchConfiguredAction())
		#expect(canvas.annotations.first?.text == "Saved")
		try pin().dispatchConfiguredAction()
		try editor().deleteButton.dispatchConfiguredAction()
		#expect(canvas.annotations.isEmpty)
		canvas.cancelCommenting()
		#expect(canvas.annotations == [annotation])
	}
}
