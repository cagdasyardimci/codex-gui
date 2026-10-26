import AppKit

/// Complete copy-control presentation with native code and terminal interaction presets.
@MainActor
class DesktopCopyButton: NSButton
{
	enum Presentation
	{
		case code, terminal

		var sideLength: CGFloat
		{
			self == .code ? 32 : 24
		}

		var iconSize: CGFloat
		{
			self == .code ? LayoutTokens.LayoutDefaults.buttonIconSize : 14
		}

		var trackingOptions: NSTrackingArea.Options
		{
			switch self
			{
			case .code:
				[.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect]
			case .terminal:
				[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
			}
		}
	}

	private let presentation: Presentation
	private var hoverTrackingArea: NSTrackingArea?
	private var copyImage: NSImage?
	private var revealState = DesktopActionRevealState()
	private var tooltipText: String?
	private let tooltip = DesktopTooltip()

	var controlCursor: NSCursor
	{
		.arrow
	}
	var isHovered: Bool
	{
		revealState.isHovered
	}
	var isGlyphVisible: Bool
	{
		presentation == .code || revealState.isRevealed
	}
	var isTooltipVisible: Bool
	{
		tooltip.isVisible
	}
	var tooltipTask: Task<Void, Never>?
	{
		tooltip.task
	}

	init(
		presentation: Presentation,
		frame: NSRect = .zero
	)
	{
		self.presentation = presentation
		super.init(frame: frame)
		title = ""
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Controls.button)
		contentTintColor = .secondaryLabelColor
		imagePosition = .imageOnly
		lineBreakMode = .byTruncatingTail
		if presentation == .terminal
		{
			clipsToBounds = true
		}
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		copyImage = DesktopIcons.image(
			.copy,
			size: presentation.iconSize
		)
		tooltipText = presentation == .code ? "Copy code" : "Copy output"
		setAccessibilityHelp(tooltipText)
		setAccessibilityLabel(tooltipText)
		updateGlyphAppearance()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func configure(
		label: String,
		target: AnyObject?,
		action: Selector?
	)
	{
		self.target = target
		self.action = action
		setAccessibilityLabel(label)
		let prompt = presentation == .code ? "Copy code" : label
		if tooltipText != prompt
		{
			toolTip = prompt
		}
	}

	// Store our prompt without registering a second native tooltip.
	override var toolTip: String?
	{
		get
		{
			tooltipText
		}
		set
		{
			resetHover()
			tooltipText = newValue
			setAccessibilityHelp(newValue)
		}
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: presentation.sideLength,
			height: presentation.sideLength
		)
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		hoverTrackingArea = DesktopHoverTracking.replace(
			in: self,
			previous: hoverTrackingArea,
			options: presentation.trackingOptions
		)
		if presentation == .terminal
		{
			synchronizeHover()
		}
	}

	override func resetCursorRects()
	{
		super.resetCursorRects()
		if presentation == .code
		{
			addCursorRect(
				bounds,
				cursor: .arrow
			)
		}
	}

	override func cursorUpdate(with event: NSEvent)
	{
		if presentation == .code
		{
			NSCursor.arrow.set()
		}
		else
		{
			super.cursorUpdate(with: event)
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		if presentation == .code
		{
			tooltip.dismiss()
			NSCursor.arrow.set()
			setHovered(
				true,
				rescheduling: true
			)
		}
		else if window == nil
		{
			setHovered(true)
		}
		else
		{
			synchronizeHover()
		}
	}

	override func mouseExited(with event: NSEvent)
	{
		resetHover()
	}

	override func mouseDown(with event: NSEvent)
	{
		if presentation == .code
		{
			tooltip.dismiss()
		}
		super.mouseDown(with: event)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if presentation == .code
		{
			resetInteraction()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if presentation == .terminal
		{
			revealState.isKeyboardFocused = false
			resetHover()
		}
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		revealState.isKeyboardFocused = accepted
		updateGlyphAppearance()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			revealState.isKeyboardFocused = false
		}
		updateGlyphAppearance()
		return accepted
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isHovered && (presentation == .terminal || isEnabled)
		{
			NSColor.labelColor.withAlphaComponent(presentation == .code ? 0.1 : 0.06).setFill()
			let diameter = min(
				bounds.width,
				bounds.height
			)
			let hoverRect = presentation == .terminal ? bounds
				: NSRect(
					x: bounds.midX - diameter / 2,
					y: bounds.midY - diameter / 2,
					width: diameter,
					height: diameter
				)
			NSBezierPath(ovalIn: hoverRect).fill()
		}
		super.draw(dirtyRect)
	}

	func setCopyImage(_ image: NSImage)
	{
		copyImage = image
		updateGlyphAppearance()
	}

	func resetInteraction()
	{
		resetHover()
	}

	func resetHover()
	{
		revealState.isHovered = false
		tooltip.dismiss()
		updateGlyphAppearance()
	}

	private func updateGlyphAppearance()
	{
		image = isGlyphVisible ? copyImage : nil
		contentTintColor = presentation == .code && isHovered ? .labelColor : .secondaryLabelColor
		needsDisplay = true
	}

	private func synchronizeHover()
	{
		guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor
		else
		{
			resetHover()
			return
		}
		let point = convert(
			window.mouseLocationOutsideOfEventStream,
			from: nil
		)
		setHovered(visibleRect.intersection(bounds).contains(point))
	}

	private func setHovered(
		_ hovered: Bool,
		rescheduling: Bool = false
	)
	{
		guard rescheduling || hovered != isHovered
		else
		{
			return
		}
		guard hovered
		else
		{
			resetHover()
			return
		}
		revealState.isHovered = true
		updateGlyphAppearance()
		tooltip.show(
			tooltipText ?? "",
			relativeTo: self
		)
		{
			[weak self] in
			guard let self, self.isHovered
			else
			{
				return false
			}
			return self.presentation == .code || self.window?.isVisible == true
		}
	}
}
