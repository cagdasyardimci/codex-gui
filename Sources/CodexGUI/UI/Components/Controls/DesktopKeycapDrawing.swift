import AppKit

/// Shared keycap fill; callers retain the shortcut's geometry and text styling.
@MainActor
enum DesktopKeycapDrawing
{
	static func fill(
		_ rect: NSRect,
		color: NSColor,
		cornerRadius: CGFloat
	)
	{
		color.setFill()
		NSBezierPath(
			roundedRect: rect,
			xRadius: cornerRadius,
			yRadius: cornerRadius
		).fill()
	}
}
