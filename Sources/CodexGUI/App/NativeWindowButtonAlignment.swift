import AppKit

/// Moves native window controls without replacing their cells, actions or accessibility.
@MainActor
final class NativeWindowButtonAlignment
{
	private var placements: [ObjectIdentifier: Placement] = [:]
	private var isUpdating = false
	private weak var window: NSWindow?

	private struct Placement
	{
		let nativeFrame: NSRect
		let alignedFrame: NSRect
	}

	func update(in window: NSWindow)
	{
		guard !isUpdating
		else
		{
			return
		}
		isUpdating = true
		defer
		{
			isUpdating = false
		}
		self.window = window
		let shouldAlign = window.toolbar?.isVisible == true
			&& window.toolbarStyle == .unifiedCompact
			&& !window.styleMask.contains(.fullScreen)
		for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton]
		{
			guard let button = window.standardWindowButton(kind), let parent = button.superview
			else
			{
				continue
			}
			let identity = ObjectIdentifier(button)
			let previous = placements[identity]
			if previous == nil
			{
				button.postsFrameChangedNotifications = true
				NotificationCenter.default.addObserver(
					self,
					selector: #selector(buttonFrameDidChange),
					name: NSView.frameDidChangeNotification,
					object: button
				)
			}
			// AppKit may reset any subset of controls during a chrome layout pass.
			// Reuse the baseline only while our last placement remains in effect.
			let nativeFrame = previous?.alignedFrame == button.frame
				? previous!.nativeFrame : button.frame
			let alignedFrame = shouldAlign
				? nativeFrame.offsetBy(
					dx: LayoutTokens.NativeChrome.windowButtonOffsetX,
					dy: (parent.isFlipped ? 1 : -1) * LayoutTokens.NativeChrome
						.windowButtonOffsetY
				)
				: nativeFrame
			placements[identity] = Placement(
				nativeFrame: nativeFrame,
				alignedFrame: alignedFrame
			)
			if button.frame != alignedFrame
			{
				button.setFrameOrigin(alignedFrame.origin)
			}
		}
	}

	@objc private func buttonFrameDidChange()
	{
		if let window
		{
			update(in: window)
		}
	}
}
