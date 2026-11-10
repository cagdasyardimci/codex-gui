import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ImageCommentEditorTests
{
	@Test(.appKitIsolation) func newCommentStartsAsCapsuleAndReturnOpensSavedCommentAsEditor(
	) throws
	{
		let canvas = ImageCommentCanvas(annotations: [])
		canvas.frame = NSRect(
			x: 0,
			y: 0,
			width: 600,
			height: 400
		)
		canvas.imageRect = canvas.bounds
		canvas.beginCommenting()
		canvas.addComment(at: NSPoint(
			x: 200,
			y: 200
		))
		let pending = try #require(canvas.subviews.compactMap
		{
			$0 as? ImageCommentEditor
		}.first)
		let input = try #require(pending.inputField)
		#expect(pending.frame.height == 44)
		#expect(input.placeholderAttributedString?.string == "Add a comment…")
		#expect(pending.textView.superview == nil)
		#expect(pending.saveButton.isHidden)
		input.stringValue = "Review this corner"
		pending.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
		#expect(!pending.saveButton.isHidden)
		#expect(pending.control(
			input,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.insertNewline(_:))
		))
		#expect(canvas.annotations.map(\.text) == ["Review this corner"])
		#expect(!canvas.subviews.contains
		{
			$0 is ImageCommentEditor
		})
		let pin = try #require(canvas.subviews.compactMap
		{
			$0 as? DesktopActionButton
		}.first)
		#expect(pin.dispatchConfiguredAction())
		let saved = try #require(canvas.subviews.compactMap
		{
			$0 as? ImageCommentEditor
		}.first)
		#expect(saved.inputField == nil)
		#expect(saved.frame.height == 120)
		#expect(saved.textView.string == "Review this corner")
		#expect(!saved.deleteButton.isHidden)
		#expect(!saved.cancelButton.isHidden)
		#expect(!saved.textView(
			saved.textView,
			doCommandBy: #selector(NSResponder.insertNewline(_:))
		))
	}

	@Test(.appKitIsolation) func activeInputKeepsTheCenteredViewportAndSelectionWhenResized() throws
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 180
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
		let capsule = ImageCommentEditor(
			text: "Example comment",
			existing: false
		)
		window.contentView?.addSubview(capsule)
		capsule.frame = NSRect(
			x: 40,
			y: 40,
			width: 294,
			height: 44
		)
		capsule.layoutSubtreeIfNeeded()
		let field = try #require(capsule.inputField)
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)
		editor.setSelectedRange(NSRange(
			location: 2,
			length: 3
		))
		for width in [CGFloat(294), 220]
		{
			capsule.frame.size.width = width
			capsule.layoutSubtreeIfNeeded()
			let viewport = try #require(editor.superview)
			let rect = field.convert(
				viewport.bounds,
				from: viewport
			)
			#expect(abs(rect.midY - field.bounds.midY) < 0.5)
			let caret = editor.firstRect(
				forCharacterRange: NSRange(
					location: 2,
					length: 0
				),
				actualRange: nil
			)
			let fieldOnScreen = window.convertToScreen(field.convert(
				field.bounds,
				to: nil
			))
			#expect(abs(caret.midY - fieldOnScreen.midY) < 1)
			#expect(editor.selectedRange() == NSRange(
				location: 2,
				length: 3
			))
		}
	}

	@Test(.appKitIsolation) func capsuleAndPinKeepOverlayContrastInBothWindowAppearances() throws
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 180
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
		// Use image artwork behind the annotation overlay in both window appearances.
		let host = DesktopSurface(.black)
		window.contentView = host
		let pin = DesktopActionButton(
			title: "1",
			presentation: .annotationPin
		)
		pin.frame = NSRect(
			x: 16,
			y: 75,
			width: 30,
			height: 30
		)
		host.addSubview(pin)
		let capsule = ImageCommentEditor(
			text: "asd",
			existing: false
		)
		capsule.frame = NSRect(
			x: 58,
			y: 68,
			width: 294,
			height: 44
		)
		host.addSubview(capsule)
		for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
		{
			window.appearance = NSAppearance(named: appearance)
			host.layoutSubtreeIfNeeded()
			let field = try #require(capsule.inputField)
			#expect(capsule.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
			#expect(capsule.saveButton.effectiveAppearance
				.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
			#expect(!capsule.saveButton.isHidden)
			#expect(field.frame.height == 28)
			let lineRect = try #require(field.cell).drawingRect(forBounds: field.bounds)
			#expect(abs(lineRect.midY - field.bounds.midY) < 0.01)
			#expect(lineRect.height < field.bounds.height)
			#expect(capsule.bounds.contains(capsule.convert(
				field.bounds,
				from: field
			)))
			let capture = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
			host.cacheDisplay(
				in: host.bounds,
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
			)).write(to: directory.appendingPathComponent("bubble-\(name).png"))
		}
	}
}
