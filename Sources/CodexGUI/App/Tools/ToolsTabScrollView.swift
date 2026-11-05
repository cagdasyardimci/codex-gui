import AppKit

/// Reveals a newly selected tab after the toolbar has settled its clip-view geometry.
@MainActor
final class ToolsTabScrollView: NSScrollView
{
	private weak var selectedTab: NSView?
	private var needsSelectionReveal = false

	func revealSelectedTab(_ tab: NSView?)
	{
		selectedTab = tab
		needsSelectionReveal = tab != nil
		needsLayout = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		requestSelectionReveal()
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		let widthChanged = frame.width != newSize.width
		super.setFrameSize(newSize)
		if widthChanged
		{
			requestSelectionReveal()
		}
	}

	private func requestSelectionReveal()
	{
		guard selectedTab != nil
		else
		{
			return
		}
		needsSelectionReveal = true
		needsLayout = true
	}

	override func layout()
	{
		super.layout()
		guard needsSelectionReveal, window != nil, contentView.bounds.width > 0,
				let selectedTab, selectedTab.superview === documentView
		else
		{
			return
		}
		documentView?.layoutSubtreeIfNeeded()
		needsSelectionReveal = false
		selectedTab.scrollToVisible(selectedTab.bounds)
	}
}
