import AppKit

/// Native vector artwork transcribed from the supplied pinned-summary screenshots.
@MainActor
enum PinnedSummaryIcons
{
	enum Glyph: CaseIterable
	{
		case changes, viewAll, toggle, plus, ellipsis, appTools, webSearch
		case agentPink, agentPurple, agentOrange, agentGreen

		var isAgent: Bool
		{
			switch self
			{
			case .agentPink, .agentPurple, .agentOrange, .agentGreen: true
			default: false
			}
		}
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
		image.isTemplate = !glyph.isAgent
		image.accessibilityDescription = accessibilityDescription
		return image
	}

	static func agentImages(size: CGFloat = 16) -> [NSImage]
	{
		[Glyph.agentPink, .agentPurple, .agentOrange, .agentGreen].map
		{
			image(
				$0,
				size: size
			)
		}
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
		case .agentPink:
			drawPinkAgent()
		case .agentPurple:
			drawPurpleAgent()
		case .agentOrange:
			drawOrangeAgent()
		case .agentGreen:
			drawGreenAgent()
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

	private static func rotated(
		_ angle: CGFloat,
		draw: () -> Void
	)
	{
		NSGraphicsContext.saveGraphicsState()
		let transform = NSAffineTransform()
		transform.translateX(
			by: 12,
			yBy: 12
		)
		transform.rotate(byDegrees: angle)
		transform.translateX(
			by: -12,
			yBy: -12
		)
		transform.concat()
		draw()
		NSGraphicsContext.restoreGraphicsState()
	}

	private static func drawPinkAgent()
	{
		for index in 0 ..< 4
		{
			rotated(CGFloat(index) * 90)
			{
				NSColor(
					calibratedRed: 0.77,
					green: 0.28,
					blue: 0.51,
					alpha: 1
				).setFill()
				NSBezierPath(ovalIn: NSRect(
					x: 6,
					y: 9,
					width: 12,
					height: 14
				)).fill()
				NSColor(
					calibratedRed: 0.96,
					green: 0.48,
					blue: 0.7,
					alpha: 0.65
				).setFill()
				NSBezierPath(ovalIn: NSRect(
					x: 8,
					y: 12,
					width: 8,
					height: 9
				)).fill()
			}
		}
		NSColor(
			calibratedRed: 0.9,
			green: 0.38,
			blue: 0.64,
			alpha: 1
		).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: 8,
			y: 8,
			width: 8,
			height: 8
		)).fill()
	}

	private static func drawPurpleAgent()
	{
		NSColor(
			calibratedRed: 0.43,
			green: 0.23,
			blue: 0.64,
			alpha: 1
		).setFill()
		polygon([NSPoint(
				x: 0,
				y: 12
			),
			NSPoint(
				x: 12,
				y: 23
			),
			NSPoint(
				x: 24,
				y: 12
			),
			NSPoint(
				x: 12,
				y: 1
			)]).fill()
		NSColor(
			calibratedRed: 0.7,
			green: 0.43,
			blue: 0.94,
			alpha: 1
		).setFill()
		for y: CGFloat in [3.5, 12, 20.5]
		{
			NSBezierPath(ovalIn: NSRect(
				x: 9.5,
				y: y - 2.5,
				width: 5,
				height: 5
			)).fill()
		}
		NSColor(
			calibratedRed: 0.89,
			green: 0.71,
			blue: 1,
			alpha: 1
		).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: 10,
			y: 10,
			width: 4,
			height: 4
		)).fill()
	}

	private static func drawOrangeAgent()
	{
		for index in 0 ..< 8
		{
			rotated(CGFloat(index) * 45)
			{
				NSColor(
					calibratedRed: 0.87,
					green: 0.5,
					blue: 0.16,
					alpha: 1
				).setFill()
				polygon([NSPoint(
						x: 8,
						y: 13
					),
					NSPoint(
						x: 9,
						y: 18
					),
					NSPoint(
						x: 12,
						y: 24
					),
					NSPoint(
						x: 14,
						y: 18
					),
					NSPoint(
						x: 17,
						y: 20
					),
					NSPoint(
						x: 15,
						y: 13
					)]).fill()
				NSColor(
					calibratedRed: 1,
					green: 0.74,
					blue: 0.35,
					alpha: 1
				).setFill()
				polygon([NSPoint(
						x: 10.5,
						y: 15
					),
					NSPoint(
						x: 12,
						y: 21
					),
					NSPoint(
						x: 13,
						y: 14
					)]).fill()
			}
		}
		NSColor(
			calibratedRed: 0.65,
			green: 0.36,
			blue: 0.12,
			alpha: 1
		).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: 8,
			y: 8,
			width: 8,
			height: 8
		)).fill()
		NSColor(
			calibratedRed: 1,
			green: 0.7,
			blue: 0.3,
			alpha: 1
		).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: 10,
			y: 10,
			width: 4,
			height: 4
		)).fill()
	}

	private static func drawGreenAgent()
	{
		for index in 0 ..< 8
		{
			rotated(CGFloat(index) * 45)
			{
				NSColor(
					calibratedRed: 0.29,
					green: 0.57,
					blue: 0.24,
					alpha: 1
				).setFill()
				polygon([NSPoint(
						x: 12,
						y: 12
					),
					NSPoint(
						x: 12,
						y: 23
					),
					NSPoint(
						x: 18,
						y: 18
					)]).fill()
				NSColor(
					calibratedRed: 0.61,
					green: 0.84,
					blue: 0.43,
					alpha: 1
				).setFill()
				polygon([NSPoint(
						x: 12,
						y: 13
					),
					NSPoint(
						x: 13,
						y: 21
					),
					NSPoint(
						x: 16,
						y: 18
					)]).fill()
			}
		}
	}

	private static func polygon(_ points: [NSPoint]) -> NSBezierPath
	{
		let path = NSBezierPath()
		path.move(to: points[0])
		for point in points.dropFirst()
		{
			path.line(to: point)
		}
		path.close()
		return path
	}
}
