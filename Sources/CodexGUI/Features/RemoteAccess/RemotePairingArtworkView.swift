import AppKit

/// Decorative device artwork sized to the pairing dialog's reference header.
@MainActor
final class RemotePairingArtworkView: NSView
{
	override func draw(_ dirtyRect: NSRect)
	{
		NSGradient(
			starting: NSColor(
				srgbRed: 0.22,
				green: 0.43,
				blue: 0.97,
				alpha: 1
			),
			ending: NSColor(
				srgbRed: 0.57,
				green: 0.8,
				blue: 1,
				alpha: 1
			)
		)?.draw(
			in: bounds,
			angle: -22
		)

		NSColor.white.withAlphaComponent(0.12).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: -85,
			y: 75,
			width: 310,
			height: 190
		)).fill()
		NSBezierPath(ovalIn: NSRect(
			x: 200,
			y: -90,
			width: 300,
			height: 280
		)).fill()

		let screen = NSRect(
			x: 44,
			y: 12,
			width: 231,
			height: 165
		)
		NSColor(
			white: 0.08,
			alpha: 1
		).setFill()
		NSBezierPath(
			roundedRect: screen,
			xRadius: 9,
			yRadius: 9
		).fill()
		let display = screen.insetBy(
			dx: 5,
			dy: 6
		)
		NSColor.white.setFill()
		NSBezierPath(rect: display).fill()
		NSColor(
			white: 0.96,
			alpha: 1
		).setFill()
		NSBezierPath(rect: NSRect(
			x: display.minX,
			y: display.minY,
			width: 48,
			height: display.height
		)).fill()
		NSColor(
			white: 0.82,
			alpha: 1
		).setFill()
		for row in 0 ..< 6
		{
			NSBezierPath(
				roundedRect: NSRect(
					x: display.minX + 8,
					y: display.maxY - 30 - CGFloat(row) * 18,
					width: row.isMultiple(of: 2) ? 32 : 26,
					height: 3
				),
				xRadius: 1.5,
				yRadius: 1.5
			).fill()
		}
		NSColor(
			white: 0.89,
			alpha: 1
		).setFill()
		NSBezierPath(
			roundedRect: NSRect(
				x: display.minX + 65,
				y: display.midY - 5,
				width: 98,
				height: 10
			),
			xRadius: 5,
			yRadius: 5
		).fill()
		NSColor(
			white: 0.24,
			alpha: 1
		).setFill()
		NSBezierPath(
			roundedRect: NSRect(
				x: 35,
				y: 4,
				width: 249,
				height: 9
			),
			xRadius: 4,
			yRadius: 4
		).fill()

		NSColor(
			white: 0.89,
			alpha: 1
		).setFill()
		NSBezierPath(
			roundedRect: NSRect(
				x: 322,
				y: 58,
				width: 72,
				height: 74
			),
			xRadius: 18,
			yRadius: 18
		).fill()
		NSColor(
			white: 0.29,
			alpha: 1
		).setFill()
		for dot in 0 ..< 3
		{
			NSBezierPath(ovalIn: NSRect(
				x: 342 + CGFloat(dot) * 15,
				y: 92,
				width: 6,
				height: 6
			)).fill()
		}
	}
}
