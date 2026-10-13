import AppKit

/// Uses grayscale text antialiasing to match the sidebar reference's font smoothing policy.
class SidebarTextField: NSTextField
{
	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}
}
