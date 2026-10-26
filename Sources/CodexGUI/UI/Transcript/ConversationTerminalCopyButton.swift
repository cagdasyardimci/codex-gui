import AppKit

/// Keeps the copy target available while showing its glyph only on hover or keyboard focus.
@MainActor
final class ConversationTerminalCopyButton: NSButton
{
	private var hoverTrackingArea: NSTrackingArea?
	private var copyImage: NSImage?
	private var isKeyboardFocused = false
	private var tooltipText: String?
	// Expose this operation for lifecycle waits, including completion after cancellation.
	private(set) var tooltipTask: Task<Void, Never>?
	private var tooltipPanel: NSPanel?
	private(set) var isHovered = false

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		clipsToBounds = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	var isGlyphVisible: Bool
	{
		isHovered || isKeyboardFocused
	}

	var isTooltipVisible: Bool
	{
		tooltipPanel?.isVisible == true
	}

	// Own the short hover delay and appearance instead of registering a second system tooltip.
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

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverTrackingArea = area
		synchronizeHover()
	}

	override func mouseEntered(with event: NSEvent)
	{
		if window == nil
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

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		isKeyboardFocused = false
		resetHover()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		isKeyboardFocused = accepted
		updateGlyphAppearance()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			isKeyboardFocused = false
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
		if isHovered
		{
			NSColor.labelColor.withAlphaComponent(0.06).setFill()
			NSBezierPath(ovalIn: bounds).fill()
		}
		super.draw(dirtyRect)
	}

	func setCopyImage(_ image: NSImage)
	{
		copyImage = image
		updateGlyphAppearance()
	}

	private func updateGlyphAppearance()
	{
		// AppKit may render a button's image through its backing layer before draw(_:).
		image = isGlyphVisible ? copyImage : nil
		needsDisplay = true
	}

	func resetHover()
	{
		isHovered = false
		tooltipTask?.cancel()
		tooltipTask = nil
		if let tooltipPanel
		{
			tooltipPanel.parent?.removeChildWindow(tooltipPanel)
		}
		tooltipPanel?.orderOut(nil)
		tooltipPanel = nil
		updateGlyphAppearance()
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
		// Non-clipping AppKit views can have a visibleRect larger than their own bounds.
		setHovered(visibleRect.intersection(bounds).contains(point))
	}

	private func setHovered(_ hovered: Bool)
	{
		guard hovered != isHovered
		else
		{
			return
		}
		if !hovered
		{
			resetHover()
			return
		}
		isHovered = true
		updateGlyphAppearance()
		tooltipTask = Task
		{
			[weak self] in
			do
			{
				try await Task.sleep(for: .milliseconds(350))
			}
			catch
			{
				return
			}
			guard !Task.isCancelled, let self, self.isHovered
			else
			{
				return
			}
			self.showTooltip()
		}
	}

	private func showTooltip()
	{
		guard let text = tooltipText, !text.isEmpty, let parent = window,
				parent.isVisible, !isHiddenOrHasHiddenAncestor, tooltipPanel == nil
		else
		{
			return
		}
		let label = NSTextField(labelWithString: text)
		label.font = .systemFont(ofSize: 13)
		label.textColor = .white
		let surface = DesktopSurface(
			NSColor(
				calibratedWhite: 0.1,
				alpha: 1
			),
			cornerRadius: 12
		)
		AppKitLayout.pin(
			label,
			to: surface,
			inset: 10
		)
		let size = NSSize(
			width: label.intrinsicContentSize.width + 20,
			height: label.intrinsicContentSize.height + 20
		)
		let panel = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = true
		panel.isReleasedWhenClosed = false
		panel.animationBehavior = .none
		panel.contentView = surface
		let buttonRect = parent.convertToScreen(convert(
			bounds,
			to: nil
		))
		let screen = parent.screen?.visibleFrame ?? buttonRect
		let x = max(
			screen.minX,
			min(
				buttonRect.midX - size.width / 2,
				screen.maxX - size.width
			)
		)
		let y = buttonRect.maxY + size.height + 6 <= screen.maxY
			? buttonRect.maxY + 6 : buttonRect.minY - size.height - 6
		panel.setFrameOrigin(NSPoint(
			x: x,
			y: max(
				screen.minY,
				y
			)
		))
		parent.addChildWindow(
			panel,
			ordered: .above
		)
		panel.orderFront(nil)
		tooltipPanel = panel
	}
}
