import AppKit
import Testing

@testable import CodexGUI

@MainActor
func revealSidebarHeadingActions(containing button: NSButton) throws
{
	let heading = try #require(button.superview as? SidebarHeadingView)
	let window = try #require(heading.window)
	let event = try #require(NSEvent.enterExitEvent(
		with: .mouseEntered,
		location: heading.convert(
			NSPoint(
				x: heading.bounds.midX,
				y: heading.bounds.midY
			),
			to: nil
		),
		modifierFlags: [],
		timestamp: 0,
		windowNumber: window.windowNumber,
		context: nil,
		eventNumber: 0,
		trackingNumber: 0,
		userData: nil
	))
	heading.mouseEntered(with: event)
	try #require(!button.isHiddenOrHasHiddenAncestor)
}
