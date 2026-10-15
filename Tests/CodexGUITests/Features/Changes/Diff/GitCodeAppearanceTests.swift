import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct GitCodeAppearanceTests
{
	@Test(
		arguments: [GitDiffRowKind.addition, .deletion],
		[false, true]
	)
	func storedWordHighlightFollowsAppearanceWithoutChangingSelection(
		kind: GitDiffRowKind,
		rerenderWithWordWrap: Bool
	) throws
	{
		_ = NSApplication.shared
		let row = GitDiffRow(
			id: "changed",
			kind: kind,
			text: "value",
			oldLine: 1,
			newLine: 1,
			changedRanges: [NSRange(
				location: 0,
				length: 5
			)]
		)
		let code = GitUnifiedCodeView(
			rows: [row],
			path: "a.txt",
			gutterMode: .new
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 100
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		// Appearance belongs to this fixture; changing NSApp would recolor concurrent windows.
		window.appearance = NSAppearance(named: .aqua)
		window.contentView = code
		defer
		{
			window.close()
		}
		let scroll = try #require(code.subviews.first as? NSScrollView)
		let text = try #require(scroll.documentView as? NSTextView)
		let selection = NSRange(
			location: 0,
			length: 3
		)
		text.setSelectedRange(selection)
		#expect(window.makeFirstResponder(text))
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			if rerenderWithWordWrap
			{
				code.wrapsCode.toggle()
			}
			let stored = try #require(text.textStorage?.attribute(
				.backgroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			let actual = try #require(stored.usingColorSpace(.deviceRGB))
			var expected: NSColor?
			code.effectiveAppearance.performAsCurrentDrawingAppearance
			{
				let semantic: NSColor = kind == .addition ? .systemGreen : .systemRed
				expected = semantic.usingColorSpace(.deviceRGB)
			}
			let color = try #require(expected)
			#expect(abs(actual.redComponent - color.redComponent) < 0.01)
			#expect(abs(actual.greenComponent - color.greenComponent) < 0.01)
			#expect(abs(actual.blueComponent - color.blueComponent) < 0.01)
			#expect(abs(actual.alphaComponent - 0.30) < 0.01)
			#expect(text.string == "value")
			#expect(text.selectedRange() == selection)
			#expect(window.firstResponder === text)
		}
	}
}
