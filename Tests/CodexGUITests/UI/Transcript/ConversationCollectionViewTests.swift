import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationCollectionViewTests
{
	@Test(.appKitIsolation) func forwardedTabUsesFocusedDescendantAsNavigationAnchor() throws
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 300,
				height: 120
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
		let collection = ConversationCollectionView(frame: NSRect(
			x: 0,
			y: 0,
			width: 300,
			height: 120
		))
		let first = DesktopStyledButton(
			title: "First",
			target: nil,
			action: nil
		)
		let second = DesktopStyledButton(
			title: "Second",
			target: nil,
			action: nil
		)
		first.keyboardFocusPolicy = .dialog
		second.keyboardFocusPolicy = .dialog
		collection.addSubview(first)
		collection.addSubview(second)
		window.contentView = collection
		window.autorecalculatesKeyViewLoop = false
		collection.nextKeyView = first
		first.nextKeyView = second
		second.nextKeyView = collection
		#expect(window.makeFirstResponder(first))
		collection.insertTab(nil)
		#expect(window.firstResponder === second)
		collection.insertBacktab(nil)
		#expect(window.firstResponder === first)
	}
}
