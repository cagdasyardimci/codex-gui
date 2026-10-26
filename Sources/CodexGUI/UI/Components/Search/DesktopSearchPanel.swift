import AppKit

/// Search content uses the shared popover host with a window-bounded viewport.
@MainActor
final class DesktopSearchPanel: NSObject
{
	enum Placement
	{
		case centered, belowAnchor
	}

	var onKeyDown: ((NSEvent) -> Bool)?
	{
		get
		{
			host.onKeyDown
		}
		set
		{
			host.onKeyDown = newValue
		}
	}
	var isShown: Bool
	{
		host.isShown
	}
	private let host: DesktopPopoverHost

	init(
		controller: NSViewController,
		placement: Placement,
		size: NSSize
	)
	{
		host = DesktopPopoverHost(
			presentation: .search(
				placement: placement == .centered ? .centered : .belowAnchor,
				size: size
			),
			content: controller.view,
			controller: controller,
			nativeShadow: true
		)
		super.init()
	}

	func show(
		relativeTo rect: NSRect,
		of anchor: NSView
	)
	{
		// Search follows the complete anchor bounds, as in its original presentation contract.
		host.show(from: anchor)
	}

	func close()
	{
		host.close()
	}
}
