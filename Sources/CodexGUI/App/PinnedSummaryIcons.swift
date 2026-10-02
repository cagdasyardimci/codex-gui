import AppKit

/// Native vector artwork transcribed from the supplied pinned-summary screenshots.
@MainActor
enum PinnedSummaryIcons
{
	enum Glyph: CaseIterable
	{
		case changes, viewAll, toggle, plus, ellipsis, appTools, webSearch


	}

	static func image(
		_ glyph: Glyph,
		size: CGFloat = 16,
		accessibilityDescription: String? = nil
	) -> NSImage
	{
		if glyph == .appTools
		{
			return DesktopIcons.image(
				.openaiLogoRegular,
				size: size,
				accessibilityDescription: accessibilityDescription
			)
		}
		let image = NSImage(
			size: NSSize(
				width: size,
				height: size
			),
			flipped: false
		)
		{
			bounds in
			NSGraphicsContext.saveGraphicsState()
			let transform = AffineTransform(scale: bounds.width / 24)
			(transform as NSAffineTransform).concat()
			draw(glyph)
			NSGraphicsContext.restoreGraphicsState()
			return true
		}
		image.isTemplate = true
		image.accessibilityDescription = accessibilityDescription
		return image
	}

	private static func draw(_ glyph: Glyph)
	{
		NSColor.black.setStroke()
		NSColor.black.setFill()
		switch glyph
		{
		case .changes:
			stroke(NSBezierPath(
				roundedRect: NSRect(
					x: 3,
					y: 2,
					width: 18,
					height: 20
				),
				xRadius: 3.5,
				yRadius: 3.5
			))
			line([NSPoint(
				x: 9,
				y: 15
			), NSPoint(
				x: 15,
				y: 15
			)])
			line([NSPoint(
				x: 12,
				y: 12
			), NSPoint(
				x: 12,
				y: 18
			)])
			line([NSPoint(
				x: 9,
				y: 7
			), NSPoint(
				x: 15,
				y: 7
			)])
		case .viewAll:
			line([NSPoint(
				x: 6,
				y: 6
			), NSPoint(
				x: 12,
				y: 12
			), NSPoint(
				x: 18,
				y: 18
			)])
			for center in [NSPoint(
				x: 5,
				y: 5
			), NSPoint(
				x: 12,
				y: 12
			), NSPoint(
				x: 19,
				y: 19
			)]
			{
				let circle = NSBezierPath(ovalIn: NSRect(
					x: center.x - 3.5,
					y: center.y - 3.5,
					width: 7,
					height: 7
				))
				NSColor.clear.setFill()
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current?.compositingOperation = .copy
				circle.fill()
				NSGraphicsContext.restoreGraphicsState()
				stroke(circle)
			}
		case .toggle:
			for y: CGFloat in [6.5, 17.5]
			{
				stroke(NSBezierPath(ovalIn: NSRect(
					x: 2,
					y: y - 3,
					width: 6,
					height: 6
				)))
				line([NSPoint(
					x: 12,
					y: y
				), NSPoint(
					x: 22,
					y: y
				)])
			}
		case .plus:
			line([NSPoint(
				x: 3,
				y: 12
			), NSPoint(
				x: 21,
				y: 12
			)])
			line([NSPoint(
				x: 12,
				y: 3
			), NSPoint(
				x: 12,
				y: 21
			)])
		case .ellipsis:
			for x: CGFloat in [4, 12, 20]
			{
				NSBezierPath(ovalIn: NSRect(
					x: x - 1.5,
					y: 10.5,
					width: 3,
					height: 3
				)).fill()
			}
		case .webSearch:
			stroke(NSBezierPath(ovalIn: NSRect(
				x: 2,
				y: 2,
				width: 20,
				height: 20
			)))
			stroke(NSBezierPath(ovalIn: NSRect(
				x: 7,
				y: 2,
				width: 10,
				height: 20
			)))
			line([NSPoint(
				x: 2,
				y: 12
			), NSPoint(
				x: 22,
				y: 12
			)])
		case .appTools:
			break

		}
	}

	private static func stroke(
		_ path: NSBezierPath,
		width: CGFloat = 1.8
	)
	{
		path.lineWidth = width
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		path.stroke()
	}

	private static func line(_ points: [NSPoint])
	{
		let path = NSBezierPath()
		path.move(to: points[0])
		for point in points.dropFirst()
		{
			path.line(to: point)
		}
		stroke(path)
	}

}
