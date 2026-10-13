import AppKit

/// Shared contours for painted surfaces, borders and shadow masks.
@MainActor
enum AppKitShapePath
{
	static func roundedCGPath(
		_ rect: NSRect,
		radius: CGFloat,
		curve: ShapeTokens.CornerCurve
	) -> CGPath
	{
		if case .circular = curve
		{
			return CGPath(
				roundedRect: rect,
				cornerWidth: radius,
				cornerHeight: radius,
				transform: nil
			)
		}
		return roundedRect(
			rect,
			radius: radius,
			curve: curve
		).cgPath
	}

	static func roundedRect(
		_ rect: NSRect,
		radius: CGFloat,
		curve: ShapeTokens.CornerCurve
	) -> NSBezierPath
	{
		let radius = max(
			0,
			min(
				radius,
				min(
					rect.width,
					rect.height
				) / 2
			)
		)
		guard case let .superellipse(parameter) = curve, radius > 0
		else
		{
			return NSBezierPath(
				roundedRect: rect,
				xRadius: radius,
				yRadius: radius
			)
		}
		// CSS Borders 4 defines x^(2^K) + y^(2^K) = 1, rather than exponent K.
		let power = 2 / pow(
			2,
			parameter
		)
		let path = NSBezierPath()
		let centers = [
			NSPoint(
				x: rect.maxX - radius,
				y: rect.maxY - radius
			),
			NSPoint(
				x: rect.minX + radius,
				y: rect.maxY - radius
			),
			NSPoint(
				x: rect.minX + radius,
				y: rect.minY + radius
			),
			NSPoint(
				x: rect.maxX - radius,
				y: rect.minY + radius
			),
		]
		// Sampling resolution is a renderer tolerance, not a design input. At these control
		// radii the chord error is below 0.01 pt, including the near-flat end segments.
		let segments = 128
		for (quadrant, center) in centers.enumerated()
		{
			for step in 0 ... segments
			{
				let angle = CGFloat(quadrant) * .pi / 2
					+ CGFloat(step) / CGFloat(segments) * .pi / 2
				let cosine = cos(angle)
				let sine = sin(angle)
				let point = NSPoint(
					x: center.x + radius * copysign(
						pow(
							abs(cosine),
							power
						),
						cosine
					),
					y: center.y + radius * copysign(
						pow(
							abs(sine),
							power
						),
						sine
					)
				)
				if quadrant == 0 && step == 0
				{
					path.move(to: point)
				}
				else
				{
					path.line(to: point)
				}
			}
		}
		path.close()
		return path
	}
}
