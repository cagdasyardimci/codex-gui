import AppKit

@MainActor
extension NSWindow
{
	/// Synthetic fixtures own their window lifetime and do not exercise system order transitions.
	func prepareForTesting()
	{
		isReleasedWhenClosed = false
		animationBehavior = .none
	}
}
