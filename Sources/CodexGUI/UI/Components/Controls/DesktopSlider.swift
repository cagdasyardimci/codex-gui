import AppKit

/// AppKit owns tracking, keyboard increments and accessibility.
/// The cell owns the shared track and thumb.
@MainActor
final class DesktopSlider: NSSlider
{
	private var observation: ThemeColorObservation?

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		cell = DesktopSliderCell()
		observation = ThemeColorObservation(view: self)
		{
			[weak self] in self?.needsDisplay = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

@MainActor
private final class DesktopSliderCell: NSSliderCell
{
	override var knobThickness: CGFloat
	{
		20
	}

	override func drawBar(
		inside rect: NSRect,
		flipped: Bool
	)
	{
		let track = NSRect(
			x: rect.minX,
			y: rect.midY - 1,
			width: rect.width,
			height: 2
		)
		((controlView as? NSSlider)?.trackFillColor ?? AppKitColorTokens.accent).setFill()
		NSBezierPath(
			roundedRect: track,
			xRadius: 1,
			yRadius: 1
		).fill()
	}

	override func drawKnob(_ knobRect: NSRect)
	{
		let thumb = NSRect(
			x: knobRect.midX - 10,
			y: knobRect.midY - 10,
			width: 20,
			height: 20
		)
		AppKitColorTokens.switchThumb(on: true).setFill()
		NSBezierPath(ovalIn: thumb).fill()
	}
}
