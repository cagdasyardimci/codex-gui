import AppKit

/// Scrolls overflowing text within its fixed frame while the row is hovered.
final class HoverScrollingTextField: SidebarTextField
{
	private var scrollTimer: Timer?
	private var hoverStartedAt: TimeInterval = 0
	private var isHovered = false
	private(set) var scrollOffset: CGFloat = 0

	override var stringValue: String
	{
		didSet
		{
			if oldValue != stringValue
			{
				restartScrolling()
			}
		}
	}

	private var title: NSAttributedString
	{
		NSAttributedString(
			string: stringValue,
			attributes: [
				.font: font ?? NSFont.systemFont(ofSize: 14),
				.foregroundColor: textColor ?? NSColor.labelColor,
			]
		)
	}

	private var textBounds: NSRect
	{
		cell?.drawingRect(forBounds: bounds) ?? bounds
	}

	func setHovered(_ hovered: Bool)
	{
		guard isHovered != hovered
		else
		{
			return
		}
		isHovered = hovered
		restartScrolling()
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		let hasFrameSizeChanged = frame.size != newSize
		super.setFrameSize(newSize)
		if hasFrameSizeChanged
		{
			restartScrolling()
		}
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			setHovered(false)
		}
		super.viewWillMove(toWindow: newWindow)
	}

	private func restartScrolling()
	{
		scrollTimer?.invalidate()
		scrollTimer = nil
		scrollOffset = 0
		needsDisplay = true
		guard isHovered, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
				title.size().width > textBounds.width, textBounds.width > 0
		else
		{
			return
		}
		hoverStartedAt = ProcessInfo.processInfo.systemUptime
		let timer = Timer(
			timeInterval: 1.0 / 60,
			repeats: true
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				guard let self
				else
				{
					return
				}
				let elapsedHoverTime = ProcessInfo.processInfo.systemUptime - self.hoverStartedAt
				self.advanceScrolling(elapsed: elapsedHoverTime)
			}
		}
		RunLoop.main.add(
			timer,
			forMode: .common
		)
		scrollTimer = timer
	}

	/// Elapsed time keeps movement independent of timer frequency.
	func advanceScrolling(elapsed: TimeInterval)
	{
		guard isHovered, scrollTimer != nil
		else
		{
			return
		}
		let overflowWidth = max(
			0,
			title.size().width - textBounds.width
		)
		let initialHoverDelay: TimeInterval = 0.6
		let pointsPerSecond: CGFloat = 30
		let scrollingDuration = max(
			0,
			elapsed - initialHoverDelay
		)
		let desiredScrollOffset = CGFloat(scrollingDuration) * pointsPerSecond
		scrollOffset = min(
			overflowWidth,
			desiredScrollOffset
		)
		if scrollOffset >= overflowWidth
		{
			scrollTimer?.invalidate()
			scrollTimer = nil
		}
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let shouldDrawScrolledText = isHovered && (scrollTimer != nil || scrollOffset > 0)
		guard shouldDrawScrolledText
		else
		{
			super.draw(dirtyRect)
			return
		}
		let text = title
		let rect = textBounds
		DesktopTextRendering.withFontSmoothingDisabled
		{
			NSBezierPath(rect: rect).addClip()
			text.draw(at: NSPoint(
				x: rect.minX - scrollOffset,
				y: rect.midY - text.size().height / 2
			))
		}
	}

	isolated deinit
	{
		scrollTimer?.invalidate()
	}
}
