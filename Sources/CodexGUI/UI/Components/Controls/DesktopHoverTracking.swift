import AppKit

/// Replaces a view's owned hover area without changing its activation or pointer policy.
@MainActor
enum DesktopHoverTracking
{
	static func replace(
		in view: NSView,
		previous: NSTrackingArea?,
		options: NSTrackingArea.Options = [
			.mouseEnteredAndExited,
			.activeInKeyWindow,
			.inVisibleRect
		]
	) -> NSTrackingArea
	{
		if let previous
		{
			view.removeTrackingArea(previous)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: options,
			owner: view,
			userInfo: nil
		)
		view.addTrackingArea(area)
		return area
	}
}
