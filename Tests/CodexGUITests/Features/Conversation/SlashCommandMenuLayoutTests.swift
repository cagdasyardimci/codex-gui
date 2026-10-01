import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Slash menu layout",
	.serialized
)
struct SlashCommandMenuLayoutTests
{
	@Test func panelTracksAnchorWidthInsteadOfKeepingItsInitialPreferredWidth() throws
	{
		_ = NSApplication.shared
		let parent = NSWindow(
			contentRect: NSRect(
				x: 100,
				y: 100,
				width: 600,
				height: 400
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		parent.isReleasedWhenClosed = false
		let anchor = NSView(frame: NSRect(
			x: 30,
			y: 30,
			width: 430,
			height: 80
		))
		try #require(parent.contentView).addSubview(anchor)
		let menu = SlashCommandPopoverView()
		menu.render(prefix: "")
		let panel = ComposerPopoverPanel(contentViewController: menu)
		panel.matchesAnchorWidth = true
		panel.preservesParentKeyboardFocus = true
		defer
		{
			panel.close(); parent.orderOut(nil)
		}
		panel.show(
			relativeTo: anchor.bounds,
			of: anchor
		)
		let child = try #require(parent.childWindows?.first)
		child.layoutIfNeeded()
		#expect(abs(child.frame.width - 430) < 1)
		#expect(abs(menu.view.bounds.width - 430) < 1)
		anchor.setFrameSize(NSSize(
			width: 540,
			height: 80
		))
		panel.reposition()
		child.layoutIfNeeded()
		#expect(abs(child.frame.width - 540) < 1)
		#expect(abs(menu.view.bounds.width - 540) < 1)
	}

}
