import AppKit

/// Matches the reference's grayscale antialiasing while retaining native font metrics.
@MainActor
enum MarkdownTextDrawing
{
	static func withAntialiasing(_ draw: () -> Void)
	{
		guard let context = NSGraphicsContext.current?.cgContext
		else
		{
			draw()
			return
		}
		context.saveGState()
		defer
		{
			context.restoreGState()
		}
		context.setShouldSmoothFonts(false)
		draw()
	}
}
