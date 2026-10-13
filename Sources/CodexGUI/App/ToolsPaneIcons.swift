import AppKit

/// Tools artwork uses the reference's 16-unit canvas independently of summary icons.
@MainActor
enum ToolsPaneIcons
{
	private static let changesStrokeWidth: CGFloat = 1.0508

	static func changes(size: CGFloat) -> NSImage
	{
		let image = NSImage(
			size: NSSize(
				width: size,
				height: size
			),
			flipped: true
		)
		{
			bounds in
			NSGraphicsContext.saveGraphicsState()
			defer
			{
				NSGraphicsContext.restoreGraphicsState()
			}
			let transform = AffineTransform(scale: bounds.width / 16)
			(transform as NSAffineTransform).concat()
			NSColor.black.setStroke()
			let outline = NSBezierPath(
				roundedRect: NSRect(
					x: 2.6665,
					y: 2.6665,
					width: 10.667,
					height: 10.667
				),
				xRadius: 1.8665,
				yRadius: 1.8665
			)
			outline.lineWidth = changesStrokeWidth
			outline.stroke()
			for (start, end) in [
				(NSPoint(
					x: 6.3335,
					y: 6.6675
				), NSPoint(
					x: 9.6665,
					y: 6.6675
				)),
				(NSPoint(
					x: 7.9995,
					y: 5.0005
				), NSPoint(
					x: 7.9995,
					y: 8.3335
				)),
				(NSPoint(
					x: 6.3335,
					y: 10.6675
				), NSPoint(
					x: 9.6665,
					y: 10.6675
				)),
			]
			{
				let line = NSBezierPath()
				line.lineWidth = changesStrokeWidth
				line.lineCapStyle = .round
				line.move(to: start)
				line.line(to: end)
				line.stroke()
			}
			return true
		}
		image.isTemplate = true
		return image
	}
}
