import AppKit

@MainActor
enum DesktopTextRendering
{
	/// Matches grayscale CSS antialiasing without changing font variations or glyph advances.
	static func withFontSmoothingDisabled<Result>(_ draw: () -> Result) -> Result
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
		return draw()
	}
}
