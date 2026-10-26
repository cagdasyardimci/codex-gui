import AppKit

/// Shared grayscale text painting for native labels and editable fields.
@MainActor
class DesktopTextField: NSTextField
{
	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}
}
