import AppKit

/// Fades clipped output at the viewport edges without intercepting text selection.
@MainActor
final class ConversationTerminalScrollView: NSScrollView
{
	private let topFade = ConversationTerminalEdgeFade(reversed: false)
	private let bottomFade = ConversationTerminalEdgeFade(reversed: true)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		clipsToBounds = true
		topFade.identifier = NSUserInterfaceItemIdentifier("terminal-top-fade")
		bottomFade.identifier = NSUserInterfaceItemIdentifier("terminal-bottom-fade")
		addSubview(topFade)
		addSubview(bottomFade)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		updateEdgeFades()
	}

	override func reflectScrolledClipView(_ clipView: NSClipView)
	{
		super.reflectScrolledClipView(clipView)
		updateEdgeFades()
	}

	func updateEdgeFades()
	{
		guard let documentView
		else
		{
			return
		}
		let viewport = convert(
			contentView.bounds,
			from: contentView
		)
		let fadeHeight = min(
			18,
			viewport.height / 3
		)
		topFade.frame = NSRect(
			x: viewport.minX,
			y: viewport.minY,
			width: viewport.width,
			height: fadeHeight
		)
		bottomFade.frame = NSRect(
			x: viewport.minX,
			y: viewport.maxY - fadeHeight,
			width: viewport.width,
			height: fadeHeight
		)
		topFade.isHidden = contentView.bounds.minY <= 0
		bottomFade.isHidden = contentView.bounds.maxY >= documentView.frame.height - 1
	}
}

@MainActor
private final class ConversationTerminalEdgeFade: NSView
{
	private let reversed: Bool

	init(reversed: Bool)
	{
		self.reversed = reversed
		super.init(frame: .zero)
		clipsToBounds = true
		setAccessibilityElement(false)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var isFlipped: Bool
	{
		true
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSBezierPath(rect: bounds).addClip()
		let color = DesktopTheme.elevated
		let gradient = NSGradient(
			starting: color.withAlphaComponent(reversed ? 0 : 0.95),
			ending: color.withAlphaComponent(reversed ? 0.95 : 0)
		)
		gradient?.draw(
			from: NSPoint(
				x: bounds.midX,
				y: bounds.minY
			),
			to: NSPoint(
				x: bounds.midX,
				y: bounds.maxY
			),
			options: []
		)
	}
}
