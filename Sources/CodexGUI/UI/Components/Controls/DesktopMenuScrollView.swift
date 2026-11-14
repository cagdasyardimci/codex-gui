import AppKit

/// A menu viewport fades clipped rows while leaving its native scroller fully visible.
@MainActor
final class DesktopMenuScrollView: NSScrollView
{
	private let edgeMask = CAGradientLayer()

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		drawsBackground = false
		hasVerticalScroller = true
		autohidesScrollers = true
		scrollerStyle = .overlay
		contentView.wantsLayer = true
		contentView.layer?.mask = edgeMask
		edgeMask.startPoint = CGPoint(
			x: 0.5,
			y: 0
		)
		edgeMask.endPoint = CGPoint(
			x: 0.5,
			y: 1
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		refreshEdges()
	}

	override func reflectScrolledClipView(_ clipView: NSClipView)
	{
		super.reflectScrolledClipView(clipView)
		refreshEdges()
	}

	private func refreshEdges()
	{
		guard contentView.bounds.height > 0, let documentView
		else
		{
			return
		}
		let visible = contentView.documentVisibleRect
		let leadingClipped = visible.minY > documentView.bounds.minY
		let trailingClipped = visible.maxY < documentView.bounds.maxY
		let fade = min(
			0.5,
			12 / contentView.bounds.height
		)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		edgeMask.frame = contentView.layer?.bounds ?? contentView.bounds
		// These colors encode mask opacity rather than visible theme colors.
		edgeMask.colors = [leadingClipped ? NSColor.clear.cgColor : NSColor.white.cgColor,
							NSColor.white.cgColor,
							NSColor.white.cgColor,
							trailingClipped ? NSColor.clear.cgColor : NSColor.white.cgColor]
		edgeMask.locations = [
			0,
			NSNumber(value: Double(fade)),
			NSNumber(value: Double(1 - fade)),
			1
		]
		CATransaction.commit()
	}
}
