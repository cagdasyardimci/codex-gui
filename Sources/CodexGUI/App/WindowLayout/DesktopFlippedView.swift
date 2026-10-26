import AppKit

/// Top-origin document coordinates shared by native scrollable content.
@MainActor
class DesktopFlippedView: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}
