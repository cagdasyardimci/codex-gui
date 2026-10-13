import AppKit

@MainActor
final class ConversationSplitView: NSSplitView
{
	var onDividerInteractionEnded: ((Int, CGFloat?) -> Void)?
	var onDividerInteractionBegan: ((Int) -> Void)?
	var showsReviewDivider = false
	{
		didSet
		{
			if showsReviewDivider != oldValue
			{
				needsDisplay = true
			}
		}
	}

	private static let dividerHitTolerance: CGFloat = 6

	private var dividerTrackingArea: NSTrackingArea?
	private var dividerHovered = false
	private var dividerDragging = false

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let dividerTrackingArea
		{
			removeTrackingArea(dividerTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		dividerTrackingArea = area
		if let window
		{
			updateDividerHover(at: convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		updateDividerHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseMoved(with event: NSEvent)
	{
		updateDividerHover(at: convert(
			event.locationInWindow,
			from: nil
		))
	}

	override func mouseExited(with event: NSEvent)
	{
		dividerHovered = false
		needsDisplay = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	private func updateDividerHover(at location: NSPoint)
	{
		let hovered = subviews.first.map
		{
			$0.frame.width > 0
				&& isNearDivider(
					at: location.x,
					paneEdge: $0.frame.maxX
				)
				&& bounds.contains(location)
		} ?? false
		guard hovered != dividerHovered
		else
		{
			return
		}
		dividerHovered = hovered
		needsDisplay = true
	}

	private func isNearDivider(
		at horizontalPosition: CGFloat,
		paneEdge: CGFloat
	) -> Bool
	{
		let distanceFromDivider = abs(horizontalPosition - paneEdge - dividerThickness / 2)
		return distanceFromDivider <= Self.dividerHitTolerance
	}

	override func mouseDown(with event: NSEvent)
	{
		let location = convert(
			event.locationInWindow,
			from: nil
		)
		let dividerIndex = subviews.indices.dropLast().first
		{
			isNearDivider(
				at: location.x,
				paneEdge: subviews[$0].frame.maxX
			)
		}
		dividerDragging = dividerIndex == 0
		needsDisplay = true
		if let dividerIndex
		{
			onDividerInteractionBegan?(dividerIndex)
		}
		super.mouseDown(with: event)
		dividerDragging = false
		if let window
		{
			updateDividerHover(at: convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
		needsDisplay = true
		if let dividerIndex
		{
			let requestedWidth: CGFloat?
			if dividerIndex == 1, let window
			{
				let release = convert(
					window.mouseLocationOutsideOfEventStream,
					from: nil
				)
				requestedWidth = bounds.maxX - release.x - dividerThickness / 2
			}
			else
			{
				requestedWidth = nil
			}
			onDividerInteractionEnded?(dividerIndex, requestedWidth)
		}
	}

	override func drawDivider(in rect: NSRect)
	{
		guard let firstPane = subviews.first,
				abs(rect.minX - firstPane.frame.maxX) > dividerThickness
		else
		{
			let shouldHighlightDivider = dividerHovered || dividerDragging
			let color = shouldHighlightDivider
				? AppKitColorTokens.highlightedPaneDivider : AppKitColorTokens.paneDivider
			color.setFill()
			rect.fill()
			return
		}
		(showsReviewDivider ? AppKitColorTokens.paneDivider : AppKitColorTokens.canvas).setFill()
		rect.fill()
	}
}
