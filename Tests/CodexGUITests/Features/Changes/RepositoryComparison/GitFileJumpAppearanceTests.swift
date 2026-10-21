import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct GitFileJumpAppearanceTests
{
	@Test func selectedResultFollowsAppearanceWithoutResettingQuerySelectionOrFocus() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 180
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		defer
		{
			window.close()
		}
		let files = ["Sources/One.swift", "Sources/Two.swift"].map
		{
			path in
			GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: "",
				hunks: []
			)
		}
		let controller = GitFileJumpPopoverController(index: GitFileJumpIndex(files: files))
		window.contentViewController = controller
		let views = descendants(controller.view)
		let search = try #require(views.compactMap
		{
			$0 as? NSSearchField
		}.first)
		search.stringValue = "Sources"
		controller.controlTextDidChange(Notification(
			name: NSControl.textDidChangeNotification,
			object: search
		))
		controller.focusSearch()
		let focus = try #require(window.firstResponder)
		let buttons = resultButtons(in: controller.view)
		try #require(buttons.count == 2)
		#expect(controller.control(
			search,
			textView: NSTextView(),
			doCommandBy: #selector(NSResponder.moveDown(_:))
		))
		var chosen: String?
		controller.onSelect =
		{
			chosen = $0
		}
		for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			controller.view.layoutSubtreeIfNeeded()
			#expect(buttons[1].appearance == nil)
			#expect(buttons[1].effectiveAppearance
				.bestMatch(from: [.aqua, .darkAqua]) == appearance)
			try expectColor(
				buttons[1].layer?.backgroundColor,
				AppKitColorTokens.searchResultSelection,
				in: buttons[1],
				alpha: 1
			)
			#expect(buttons[0].layer?.backgroundColor?.alpha == 0)
			#expect(search.stringValue == "Sources")
			#expect(window.firstResponder === focus)
			#expect(resultButtons(in: controller.view).elementsEqual(
				buttons,
				by:
				{
					$0 === $1
				}
			))
			#expect(controller.control(
				search,
				textView: NSTextView(),
				doCommandBy: #selector(NSResponder.insertNewline(_:))
			))
			#expect(chosen == "Sources/Two.swift")
		}
	}

	private func resultButtons(in view: NSView) -> [NSButton]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.filter
		{
			["Sources/One.swift", "Sources/Two.swift"].contains($0.identifier?.rawValue ?? "")
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func expectColor(
		_ actualCGColor: CGColor?,
		_ semantic: NSColor,
		in view: NSView,
		alpha: CGFloat = 1
	) throws
	{
		let actual = try #require(actualCGColor
			.flatMap
			{
				NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB)
			})
		var expected: NSColor?
		view.effectiveAppearance
			.performAsCurrentDrawingAppearance
			{
				expected = semantic.usingColorSpace(.deviceRGB)
			}
		let color = try #require(expected)
		#expect(abs(actual.redComponent - color.redComponent) < 0.01)
		#expect(abs(actual.greenComponent - color.greenComponent) < 0.01)
		#expect(abs(actual.blueComponent - color.blueComponent) < 0.01)
		#expect(abs(actual.alphaComponent - alpha) < 0.01)
	}
}
