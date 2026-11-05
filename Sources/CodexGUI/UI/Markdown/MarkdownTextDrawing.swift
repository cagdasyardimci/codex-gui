import AppKit

/// Matches the reference's grayscale antialiasing while retaining native font metrics.
@MainActor
enum MarkdownTextDrawing
{
	static func withAntialiasing(_ draw: () -> Void)
	{
		DesktopTextRendering.withFontSmoothingDisabled(draw)
	}
}
