import AppKit

@MainActor
final class ToolsTabSurface: NSView
{
	let tabID: UUID?
	private let selectionButton: ToolsTabSelectionButton
	private let isSelected: Bool
	private let shadowLayer = CALayer()
	private var isHovered = false
	private var hoverTrackingArea: NSTrackingArea?
	var onHoverChange: ((Bool) -> Void)?
	var dropEdge: CGRectEdge?
	{
		didSet
		{
			if oldValue != dropEdge
			{
				needsDisplay = true
			}
		}
	}

	init(
		selectionButton: ToolsTabSelectionButton,
		isSelected: Bool,
		tabID: UUID?
	)
	{
		self.selectionButton = selectionButton
		self.isSelected = isSelected
		self.tabID = tabID
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
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		let hit = super.hitTest(point)
		return hit === self ? selectionButton : hit
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
		drawBackground()
		if let dropEdge
		{
			let marker = bounds.insetBy(
				dx: 0,
				dy: 4
			).divided(
				atDistance: 2,
				from: dropEdge
			).slice
			AppKitColorTokens.accentText.setFill()
			marker.fill()
		}
	}

	private func drawBackground()
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
