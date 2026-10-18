import AppKit

@MainActor
final class CodeCopyButton: NSButton, DesktopControlCursorProviding
{
	var controlCursor: NSCursor
	{
		.arrow
	}
	private var hoverTrackingArea: NSTrackingArea?
	private var isHovered = false
	// Capture the delayed operation to await completion or cancellation without timing margins.
	private(set) var tooltipTask: Task<Void, Never>?
	private var tooltipPanel: NSPanel?
	private var tooltipAppearance: DesktopPanelAppearanceBinding?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		hoverTrackingArea = area
	}

	override func resetCursorRects()
	{
		super.resetCursorRects()
		addCursorRect(
			bounds,
			cursor: .arrow
		)
	}

	override func cursorUpdate(with event: NSEvent)
	{
		NSCursor.arrow.set()
	}

	override func mouseEntered(with event: NSEvent)
	{
		hideCopyTooltip()
		NSCursor.arrow.set()
		isHovered = true
		contentTintColor = .labelColor
		needsDisplay = true
		tooltipTask = Task
		{
			[weak self] in
			do
			{
				try await Task.sleep(for: .milliseconds(400))
			}
			catch
			{
				return
			}
			guard !Task.isCancelled, let self
			else
			{
				return
			}
			self.showCopyTooltip()
		}
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		hideCopyTooltip()
		contentTintColor = .secondaryLabelColor
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent)
	{
		hideCopyTooltip()
		super.mouseDown(with: event)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		resetInteraction()
		super.viewWillMove(toWindow: newWindow)
	}

	func resetInteraction()
	{
		hideCopyTooltip()
		isHovered = false
		contentTintColor = .secondaryLabelColor
		needsDisplay = true
	}

	@objc private func showCopyTooltip()
	{
		guard isHovered, let window, !isHiddenOrHasHiddenAncestor
		else
		{
			return
		}
		let label = NSTextField(labelWithString: "Copy code")
		label.font = .systemFont(ofSize: 12)
		label.textColor = .labelColor
		label.sizeToFit()
		let size = NSSize(
			width: label.frame.width + 24,
			height: 28
		)
		let surface = DesktopSurface(
			AppKitColorTokens.inspector,
			cornerRadius: 12,
			bordered: true
		)
		surface.frame = NSRect(
			origin: .zero,
			size: size
		)
		label.frame.origin = NSPoint(
			x: 12,
			y: (size.height - label.frame.height) / 2
		)
		surface.addSubview(label)
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
		panel.contentView = surface
		tooltipAppearance = DesktopPanelAppearanceBinding(
			panel: panel,
			source: self
		)
		let screenRect = window.convertToScreen(convert(
			bounds,
			to: nil
		))
		panel.setFrameOrigin(NSPoint(
			x: screenRect.midX - size.width / 2,
			y: screenRect.maxY + 4
		))
		window.addChildWindow(
			panel,
			ordered: .above
		)
		tooltipPanel = panel
	}

	private func hideCopyTooltip()
	{
		tooltipTask?.cancel()
		tooltipTask = nil
		tooltipAppearance?.invalidate()
		tooltipAppearance = nil
		if let tooltipPanel
		{
			tooltipPanel.parent?.removeChildWindow(tooltipPanel)
			tooltipPanel.orderOut(nil)
		}
		tooltipPanel = nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isHovered && isEnabled
		{
			NSColor.labelColor.withAlphaComponent(0.1).setFill()
			let diameter = min(
				bounds.width,
				bounds.height
			)
			NSBezierPath(ovalIn: NSRect(
				x: bounds.midX - diameter / 2,
				y: bounds.midY - diameter / 2,
				width: diameter,
				height: diameter
			)).fill()
		}
		super.draw(dirtyRect)
	}
}
