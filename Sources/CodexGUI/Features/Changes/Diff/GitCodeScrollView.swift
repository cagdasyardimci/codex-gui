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
		if routesWheelVertically
		{
			if let outer = superview?.enclosingScrollView
			{
				outer.scrollWheel(with: event)
			}
			else
			{
				super.scrollWheel(with: event)
			}
			return
		}
		guard hasHorizontalScroller
		else
		{
			return
		}
		let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX
			: (event.modifierFlags.contains(.shift) ? event.scrollingDeltaY : 0)
		guard delta != 0
		else
		{
			return
		}
		let points = delta * (event.hasPreciseScrollingDeltas ? 1 : horizontalLineScroll)
		var proposed = contentView.bounds
		proposed.origin.x -= points
		let constrained = contentView.constrainBoundsRect(proposed)
		contentView.scroll(to: NSPoint(
			x: constrained.origin.x,
			y: contentView.bounds.origin.y
		))
		reflectScrolledClipView(contentView)
	}
}
