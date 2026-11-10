import AppKit

/// Rounded hover feedback without replacing AppKit's action, focus or accessibility handling.
@MainActor
class DesktopHoverButton: DesktopAttributedTitleButton
{
	var cornerRadius: CGFloat = 12.5
	var cornerCurve: ShapeTokens.CornerCurve = .circular
	var usesThemedKeyboardFocus = false
	{
		didSet
		{
			if usesThemedKeyboardFocus
			{
				focusRingType = .none
			}
			needsLayout = true
		}
	}
	var keyboardFocusCornerRadius: CGFloat
	{
		cornerRadius
	}
	private var keyboardFocused = false
	var hasKeyboardFocus: Bool
	{
		keyboardFocused && window?.firstResponder === self
	}
	private var focusIndicator: CAShapeLayer?
	private lazy var focusColorObservation = ThemeColorObservation
	{
		[weak self] in self?.refreshFocusIndicator()
	}
	private(set) var isHovered = false
	var hoverBackgroundColor: NSColor
	{
		AppKitColorTokens.rowHighlight
	}
	var pressedBackgroundColor: NSColor
	{
		hoverBackgroundColor
	}
	var hoverTrackingOptions: NSTrackingArea.Options
	{
		[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
	}
	var synchronizesHoverOnTrackingUpdate: Bool
	{
		false
	}
	var isBackgroundHighlighted: Bool
	{
		isEnabled && (isHovered || isHighlighted)
	}
	private var tracking: NSTrackingArea?

	override var isEnabled: Bool
	{
		didSet
		{
			needsLayout = true
		}
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if usesThemedKeyboardFocus
		{
			_ = focusColorObservation
		}
		refreshFocusIndicator()
	}

	override func layout()
	{
		super.layout()
		refreshFocusIndicator()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		keyboardFocused = accepted && NSApp.currentEvent?.type == .keyDown
		needsLayout = true
		hoverDidChange()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			keyboardFocused = false
		}
		needsLayout = true
		hoverDidChange()
		return accepted
	}

	private func refreshFocusIndicator()
	{
		guard usesThemedKeyboardFocus
		else
		{
			focusIndicator?.isHidden = true
			return
		}
		if focusIndicator == nil
		{
			wantsLayer = true
			let indicator = CAShapeLayer()
			indicator.fillColor = nil
			indicator.lineWidth = 2
			layer?.addSublayer(indicator)
			focusIndicator = indicator
		}
		guard let indicator = focusIndicator
		else
		{
			return
		}
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		indicator.isHidden = !isEnabled || !keyboardFocused || window?.firstResponder !== self
		indicator.frame = bounds
		indicator.path = CGPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			cornerWidth: keyboardFocusCornerRadius,
			cornerHeight: keyboardFocusCornerRadius,
			transform: nil
		)
		indicator.strokeColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.focus,
			for: self
		)
		CATransaction.commit()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking,
			options: hoverTrackingOptions
		)
		if synchronizesHoverOnTrackingUpdate
		{
			setHovered(window.map
			{
				visibleRect.contains(convert(
					$0.mouseLocationOutsideOfEventStream,
					from: nil
				))
			} ?? false)
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		setHovered(true)
	}

	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		clearHover()
	}

	func clearHover()
	{
		setHovered(false)
	}

	func setHovered(_ hovered: Bool)
	{
		isHovered = hovered
		needsDisplay = true
		hoverDidChange()
	}

	func hoverDidChange()
	{
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshFocusIndicator()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		drawBackground()
		super.draw(dirtyRect)
	}

	func drawBackground()
	{
		if isBackgroundHighlighted
		{
			(isHighlighted ? pressedBackgroundColor : hoverBackgroundColor).setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: cornerRadius,
				curve: cornerCurve
			).fill()
		}
	}
}
