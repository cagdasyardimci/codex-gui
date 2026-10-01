import AppKit

/// Keeps hover attached to the pointer rather than to recycled or scrolling row views.
@MainActor
final class SlashCommandMenuTableView: NSTableView
{
	private(set) var hoveredRow: Int?
	private var pointerTrackingArea: NSTrackingArea?
	private weak var observedClipView: NSClipView?

	override func viewDidMoveToSuperview()
	{
		super.viewDidMoveToSuperview()
		if let observedClipView
		{
			NotificationCenter.default.removeObserver(
				self,
				name: NSView.boundsDidChangeNotification,
				object: observedClipView
			)
		}
		observedClipView = superview as? NSClipView
		if let observedClipView
		{
			observedClipView.postsBoundsChangedNotifications = true
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(scrollPositionChanged),
				name: NSView.boundsDidChangeNotification,
				object: observedClipView
			)
		}
		refreshHoverFromPointer()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let pointerTrackingArea
		{
			removeTrackingArea(pointerTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.mouseMoved,
				.activeAlways,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		pointerTrackingArea = area
		refreshHoverFromPointer()
	}

	override func mouseEntered(with event: NSEvent)
	{
		refreshHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseMoved(with event: NSEvent)
	{
		refreshHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseExited(with event: NSEvent)
	{
		refreshHover(at: nil)
	}

	override func scrollWheel(with event: NSEvent)
	{
		super.scrollWheel(with: event)
		refreshHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func reloadData()
	{
		super.reloadData()
		refreshHoverFromPointer()
	}

	@objc private func scrollPositionChanged()
	{
		refreshHoverFromPointer()
	}

	private func refreshHoverFromPointer()
	{
		guard let window, window.isVisible
		else
		{
			refreshHover(at: nil)
			return
		}
		refreshHover(at: convert(
			window.mouseLocationOutsideOfEventStream,
			from: nil
		))
	}

	func refreshHover(at point: NSPoint?)
	{
		let hoveredRowIndex = point.flatMap
		{
			point -> Int? in
			guard visibleRect.contains(point)
			else
			{
				return nil
			}
			let index = self.row(at: point)
			guard index >= 0, index < numberOfRows,
					delegate?.tableView?(self, shouldSelectRow: index) != false
			else
			{
				return nil
			}
			return index
		}
		hoveredRow = hoveredRowIndex
		enumerateAvailableRowViews
		{
			view, index in
			(view as? SlashCommandMenuRowView)?.isHovered = index == hoveredRowIndex
		}
	}
}
