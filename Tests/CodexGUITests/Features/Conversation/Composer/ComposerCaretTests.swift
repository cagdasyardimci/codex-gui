import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ComposerCaretTests
{
	@Test func lineStartCaretRetainsItsFullRetinaWidth() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = ComposerCaretTestWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 800,
				height: 400
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 800,
			height: 400
		))
		defer
		{
			window.close()
		}
		let editor = controller.composer
		#expect(window.makeFirstResponder(editor))
		for draft in ["", "\n"]
		{
			editor.string = draft
			editor.setSelectedRange(NSRange(
				location: (draft as NSString).length,
				length: 0
			))
			controller.updateComposerHeight()
			controller.view.layoutSubtreeIfNeeded()
			editor.updateInsertionPointStateAndRestartTimer(true)
			#expect(editor.shouldDrawInsertionPoint)
			let manager = try #require(editor.layoutManager)
			let container = try #require(editor.textContainer)
			manager.ensureLayout(for: container)
			let line = manager.extraLineFragmentRect
			let caret = NSRect(
				x: -0.5,
				y: line.minY,
				width: 1,
				height: line.height
			)
			let bitmap = try renderCaret(
				editor,
				rect: caret,
				turnedOn: true
			)

			var columns: [Int] = []
			for x in 0 ..< 4
			{
				var count = 0
				for y in 0 ..< bitmap.pixelsHigh
				{
					let color = try #require(bitmap.colorAt(
						x: x,
						y: y
					)?.usingColorSpace(.sRGB))
					if color.alphaComponent > 0.8, color.redComponent < 0.2,
						color.greenComponent < 0.2, color.blueComponent < 0.2
					{
						count += 1
					}
				}
				columns.append(count)
			}
			#expect(columns[0] == Int(line.height * 2))
			#expect(columns[1] == columns[0])
			#expect(columns[2] == 0)
			#expect(columns[3] == 0)
			let off = try renderCaret(
				editor,
				rect: caret,
				turnedOn: false
			)
			for y in 0 ..< off.pixelsHigh
			{
				let color = try #require(off.colorAt(
					x: 0,
					y: y
				)?.usingColorSpace(.sRGB))
				#expect(color.alphaComponent < 0.8 || color.redComponent > 0.8)
			}
			if let directory = ProcessInfo.processInfo.environment["CODEX_GUI_CARET_CAPTURES"]
			{
				let data = try #require(bitmap.representation(
					using: .png,
					properties: [:]
				))
				let name = draft.isEmpty ? "empty" : "newline"
				try data.write(to: URL(fileURLWithPath: directory + "/caret-\(name).png"))
			}
		}

		let interior = NSRect(
			x: 10,
			y: 0,
			width: 1,
			height: 20
		)
		let actual = try renderCaret(
			editor,
			rect: interior,
			turnedOn: true
		)
		let standard = NSTextView()
		standard.appearance = editor.effectiveAppearance
		standard.insertionPointColor = editor.insertionPointColor
		let expected = try renderCaret(
			standard,
			rect: interior,
			turnedOn: true
		)
		let actualData = try #require(actual.bitmapData)
		let expectedData = try #require(expected.bitmapData)
		let byteCount = actual.bytesPerRow * actual.pixelsHigh
		#expect(Array(UnsafeBufferPointer(
			start: actualData,
			count: byteCount
		))
			== Array(UnsafeBufferPointer(
				start: expectedData,
				count: byteCount
			)))
		let ink = try #require(actual.colorAt(
			x: 20,
			y: 10
		)?.usingColorSpace(.sRGB))
		#expect(abs(ink.redComponent - 26 / 255) < 0.005)
		#expect(abs(ink.greenComponent - 28 / 255) < 0.005)
		#expect(abs(ink.blueComponent - 31 / 255) < 0.005)

		editor.string = "Text"
		editor.setSelectedRange(NSRange(
			location: 0,
			length: 2
		))
		#expect(editor.selectedRange() == NSRange(
			location: 0,
			length: 2
		))
		#expect(window.firstResponder === editor)
		#expect(window.makeFirstResponder(nil))
		#expect(window.firstResponder !== editor)
	}

	private func renderCaret(
		_ editor: NSTextView,
		rect: NSRect,
		turnedOn: Bool
	) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 128,
			pixelsHigh: 88,
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
		context.cgContext.setFillColor(NSColor.white.cgColor)
		context.cgContext.fill(CGRect(
			x: 0,
			y: 0,
			width: 128,
			height: 88
		))
		context.cgContext.translateBy(
			x: 0,
			y: 88
		)
		context.cgContext.scaleBy(
			x: 2,
			y: -2
		)
		// Direct bitmap drawing bypasses NSView's automatic appearance context.
		editor.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			editor.drawInsertionPoint(
				in: rect,
				color: editor.insertionPointColor,
				turnedOn: turnedOn
			)
		}
		return bitmap
	}

}

/// Exercises native focus drawing without presenting or activating a desktop window.
private final class ComposerCaretTestWindow: NSWindow
{
	override var isKeyWindow: Bool
	{
		true
	}
}
