import AppKit

@MainActor
final class ToolsTabSurface: NSView
{
	static let dragType = NSPasteboard.PasteboardType("com.codexgui.tools-tab-id")
	private let isSelected: Bool
	private let shadowLayer = CALayer()
	private var isHovered = false
	private var hoverTrackingArea: NSTrackingArea?
	var dragOwner: UUID?
	var onHoverChange: ((Bool) -> Void)?
	var onDrop: ((UUID, Bool) -> Void)?

	init(isSelected: Bool)
	{
		self.isSelected = isSelected
		super.init(frame: .zero)
		if isSelected
		{
			wantsLayer = true
			layer?.insertSublayer(
				shadowLayer,
				at: 0
			)
		}
		setAccessibilityElement(false)
		registerForDraggedTypes([Self.dragType])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
	{
		guard validDrag(from: sender) != nil
		else
		{
			return []
		}
		return .move
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
	{
		guard let id = validDrag(from: sender), let onDrop
		else
		{
			return false
		}
		let before = convert(
			sender.draggingLocation,
			from: nil
		).x < bounds.midX
		onDrop(
			id,
			before
		)
		return true
	}

	private func validDrag(from sender: NSDraggingInfo) -> UUID?
	{
		guard let source = sender.draggingSource as? ToolsTabSelectionButton,
				let dragOwner, source.dragOwner == dragOwner,
				source.window === window,
				let value = sender.draggingPasteboard.string(forType: Self.dragType),
				let payload = ToolsTabDragPayload(string: value),
				let sourceID = source.draggedID,
				payload.isOwned(
				by: dragOwner,
				source: ToolsTabDragPayload(
					ownerID: dragOwner,
					tabID: sourceID
				)
				), onDrop != nil
		else
		{
			return nil
		}
		return payload.tabID
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverTrackingArea = area
		if let window
		{
			let previouslyHovered = isHovered
			isHovered = bounds.contains(convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
			if previouslyHovered != isHovered
			{
				onHoverChange?(isHovered)
			}
		}
		needsDisplay = true
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		onHoverChange?(true)
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		onHoverChange?(false)
		needsDisplay = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if window == nil
		{
			isHovered = false
			onHoverChange?(false)
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateShadow()
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		updateShadow()
	}

	private func updateShadow()
	{
		guard isSelected
		else
		{
			return
		}
		AppKitShadowRenderer.apply(
			ShadowTokens.selectedTab,
			to: shadowLayer,
			in: self,
			cornerRadius: ShapeTokens.TabControls.selectedRadius,
			cornerCurve: ShapeTokens.TabControls.cornerCurve
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard isSelected || isHovered
		else
		{
			return
		}
		let path = AppKitShapePath.roundedRect(
			bounds,
			radius: ShapeTokens.TabControls.selectedRadius,
			curve: ShapeTokens.TabControls.cornerCurve
		)
		(isSelected ? AppKitColorTokens.selectedTab : AppKitColorTokens.rowHighlight).setFill()
		path.fill()
		if isSelected
		{
			// CSS backgrounds extend underneath their border. Clip a double-width outer
			// stroke to retain the configured inside edge without losing that backing fill.
			NSGraphicsContext.saveGraphicsState()
			path.addClip()
			AppKitColorTokens.selectedTabEdge.setStroke()
			path.lineWidth = ShapeTokens.TabControls.selectedEdgeWidth * 2
			path.stroke()
			NSGraphicsContext.restoreGraphicsState()
		}
	}
}
