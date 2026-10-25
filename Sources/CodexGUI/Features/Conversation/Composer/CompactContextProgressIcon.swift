import AppKit

/// The Compact command's context usage, with the filled arc starting at twelve o'clock.
@MainActor
final class CompactContextProgressIcon: NSView
{
	private let percent: Int

	init(percent: Int)
	{
		self.percent = min(
			100,
			max(
				0,
				percent
			)
		)
		super.init(frame: .zero)
		widthAnchor.constraint(equalToConstant: 16).isActive = true
		heightAnchor.constraint(equalToConstant: 16).isActive = true
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		let center = NSPoint(
			x: bounds.midX,
			y: bounds.midY
		)
		let radius = min(
			bounds.width,
			bounds.height
		) / 2 - 2
		let track = NSBezierPath(ovalIn: NSRect(
			x: center.x - radius,
			y: center.y - radius,
			width: radius * 2,
			height: radius * 2
		))
		track.lineWidth = 2.5
		NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
		track.stroke()

		guard percent > 0
		else
		{
			return
		}
		let progress = NSBezierPath()
		progress.appendArc(
			withCenter: center,
			radius: radius,
			startAngle: 90,
			endAngle: 90 - CGFloat(percent) * 3.6,
			clockwise: true
		)
		progress.lineWidth = 2.5
		progress.lineCapStyle = .round
		NSColor.labelColor.setStroke()
		progress.stroke()
	}
}
