import AppKit

/// Code panes own horizontal scrolling; their enclosing viewer owns vertical scrolling.
@MainActor
final class GitCodeScrollView: NSScrollView, DesktopWheelInputReceiving
{
	private var routesWheelVertically = false

	override func scrollWheel(with event: NSEvent)
	{
		if event.phase.contains(.began)
		{
			routesWheelVertically = false
		}
		if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
		{
			routesWheelVertically = !event.modifierFlags.contains(.shift)
				&& event.scrollingDeltaY != 0
				&& (!hasHorizontalScroller
					|| abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX))
		}
		if routesWheelVertically, let outer = superview?.enclosingScrollView
		{
			outer.scrollWheel(with: event)
		}
		else
		{
			super.scrollWheel(with: event)
		}
	}
}
