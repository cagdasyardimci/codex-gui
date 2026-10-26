import AppKit

/// Composer-specific placement inputs for the shared native popover host.
@MainActor
final class ComposerPopoverPanel: NSObject
{
	var onPresentationChange: ((Bool) -> Void)?
	{
		get
		{
			host.onPresentationChange
		}
		set
		{
			host.onPresentationChange = newValue
		}
	}
	var preservesParentKeyboardFocus = false
	var matchesAnchorWidth = false
	var alignsToAnchorLeadingEdge = false
	var limitsHeightToSpaceAboveAnchor = false
	var horizontalOffset: CGFloat = 0
	var anchorSpacing: CGFloat = 8
	var shouldDismissForEscape: (() -> Bool)?
	{
		get
		{
			host.shouldDismissForEscape
		}
		set
		{
			host.shouldDismissForEscape = newValue
		}
	}
	weak var focusAfterDismissal: NSView?
	{
		didSet
		{
			host.focusAfterDismissal = focusAfterDismissal
		}
	}
	var isShown: Bool
	{
		host.isShown
	}
	private let host: DesktopPopoverHost

	init(
		contentViewController: NSViewController,
		hasShadow: Bool = false,
		shadowOutset: CGFloat = 0
	)
	{
		host = DesktopPopoverHost(
			presentation: .composer(DesktopPopoverHost.ComposerPlacement()),
			content: contentViewController.view,
			controller: contentViewController,
			nativeShadow: hasShadow,
			shadowOutset: shadowOutset
		)
		super.init()
	}

	func show(
		relativeTo rect: NSRect,
		of anchor: NSView
	)
	{
		host.update(.composer(placement))
		host.show(
			from: anchor,
			relativeTo: rect
		)
	}

	func close()
	{
		host.close()
	}

	func reposition()
	{
		host.update(.composer(placement))
	}

	private var placement: DesktopPopoverHost.ComposerPlacement
	{
		var placement = DesktopPopoverHost.ComposerPlacement()
		placement.alignment = alignsToAnchorLeadingEdge ? .leading : .centered
		placement.width = matchesAnchorWidth ? .anchor : .content
		placement.height = limitsHeightToSpaceAboveAnchor ? .aboveAnchor : .screen
		placement.focus = preservesParentKeyboardFocus ? .parent : .panel
		placement.horizontalOffset = horizontalOffset
		placement.anchorSpacing = anchorSpacing
		return placement
	}
}
