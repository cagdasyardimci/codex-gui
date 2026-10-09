import AppKit

@MainActor
final class AttachmentThumbnailImageView: NSImageView
{
	override func draw(_ dirtyRect: NSRect)
	{
		guard let image
		else
		{
			return
		}
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: bounds).addClip()
		AttachmentThumbnailDrawing.draw(
			image,
			in: bounds,
			respectFlipped: true
		)
		NSGraphicsContext.restoreGraphicsState()
	}
}

@MainActor
enum AttachmentThumbnailDrawing
{
	/// Fill the tile without stretching, centering the overflow on both axes.
	static func draw(
		_ image: NSImage,
		in bounds: NSRect,
		respectFlipped: Bool
	)
	{
		guard image.size.width > 0, image.size.height > 0
		else
		{
			return
		}
		let scale = max(
			bounds.width / image.size.width,
			bounds.height / image.size.height
		)
		let size = NSSize(
			width: image.size.width * scale,
			height: image.size.height * scale
		)
		image.draw(
			in: NSRect(
				x: bounds.midX - size.width / 2,
				y: bounds.midY - size.height / 2,
				width: size.width,
				height: size.height
			),
			from: .zero,
			operation: .sourceOver,
			fraction: 1,
			respectFlipped: respectFlipped,
			hints: nil
		)
	}
}
