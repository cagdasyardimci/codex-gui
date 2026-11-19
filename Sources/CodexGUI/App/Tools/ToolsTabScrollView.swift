import AppKit

/// Owns the scrollable tab viewport and the insertion point for local tab drags.
@MainActor
final class ToolsTabScrollView: NSScrollView
{
	static let dragType = NSPasteboard.PasteboardType("com.codexgui.tools-tab-id")
	var dragOwner: UUID?
	var onDrop: ((UUID, UUID, Bool) -> Bool)?
	private weak var selectedTab: NSView?
	private weak var markedTab: ToolsTabSurface?
	private var needsSelectionReveal = false

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		registerForDraggedTypes([Self.dragType])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
	{
		draggingUpdated(sender)
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation
	{
		guard dragID(from: sender) != nil
		else
		{
			clearDropMarker()
			return []
		}
		needsSelectionReveal = false
		scrollNearEdge(at: sender.draggingLocation)
		guard let target = dropTarget(at: sender.draggingLocation)
		else
		{
			clearDropMarker()
			return []
		}
		if markedTab !== target.tab
		{
			clearDropMarker()
		}
		target.tab.dropEdge = target.before ? .minXEdge : .maxXEdge
		markedTab = target.tab
		return .move
	}

	override func draggingExited(_ sender: NSDraggingInfo?)
	{
		clearDropMarker()
	}

	override func draggingEnded(_ sender: NSDraggingInfo)
	{
		clearDropMarker()
	}

	override func wantsPeriodicDraggingUpdates() -> Bool
	{
		true
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
	{
		clearDropMarker()
		guard let id = dragID(from: sender)
		else
		{
			return false
		}
		return dropTab(
			id,
			at: sender.draggingLocation
		)
	}

	func dropTab(
		_ id: UUID,
		at location: NSPoint
	) -> Bool
	{
		guard let target = dropTarget(at: location), let targetID = target.tab.tabID
		else
		{
			return false
		}
		return onDrop?(id, targetID, target.before) ?? false
	}

	private func clearDropMarker()
	{
		markedTab?.dropEdge = nil
		markedTab = nil
	}

	private func dragID(from sender: NSDraggingInfo) -> UUID?
	{
		guard let window, let dragOwner,
				let source = sender.draggingSource as? ToolsTabSelectionButton,
				source.dragWindow === window, let sourceOwner = source.dragOwner,
				let sourceID = source.draggedID,
				let value = sender.draggingPasteboard.string(forType: Self.dragType),
				let payload = ToolsTabDragPayload(string: value),
				payload.isOwned(
				by: dragOwner,
				source: ToolsTabDragPayload(
					ownerID: sourceOwner,
					tabID: sourceID
				)
				)
		else
		{
			return nil
		}
		return payload.tabID
	}

	private func dropTarget(at location: NSPoint) -> (tab: ToolsTabSurface, before: Bool)?
	{
		guard let stack = documentView as? NSStackView,
				contentView.bounds.contains(contentView.convert(
				location,
				from: nil
				))
		else
		{
			return nil
		}
		let x = stack.convert(
			location,
			from: nil
		).x
		var lastTab: ToolsTabSurface?
		for case let tab as ToolsTabSurface in stack.arrangedSubviews where tab.tabID != nil
		{
			if x < tab.frame.midX
			{
				return (tab, true)
			}
			lastTab = tab
		}
		return lastTab.map
		{
			($0, false)
		}
	}

	private func scrollNearEdge(at location: NSPoint)
	{
		let bounds = contentView.bounds
		let point = contentView.convert(
			location,
			from: nil
		)
		guard bounds.contains(point)
		else
		{
			return
		}
		let edgeWidth = min(
			24,
			bounds.width / 4
		)
		let left = max(
			0,
			bounds.minX + edgeWidth - point.x
		)
		let right = max(
			0,
			point.x - (bounds.maxX - edgeWidth)
		)
		guard left != right
		else
		{
			return
		}
		let proposed = bounds.offsetBy(
			dx: (right - left) / 2,
			dy: 0
		)
		contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
		reflectScrolledClipView(contentView)
	}

	func revealSelectedTab(
		_ tab: NSView?,
		scrollIntoView: Bool
	)
	{
		selectedTab = tab
		needsSelectionReveal = scrollIntoView && tab != nil
		needsLayout = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		clearDropMarker()
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
