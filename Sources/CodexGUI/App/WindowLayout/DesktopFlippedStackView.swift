import AppKit

/// A top-origin stack retains NSStackView's arranged-subview layout behavior.
@MainActor
final class DesktopFlippedStackView: NSStackView
{
	override var isFlipped: Bool
	{
		true
	}
}
