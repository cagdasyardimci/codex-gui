import AppKit

/// Retains action targets and captures callbacks for the lifetime of a native menu.
@MainActor
class NavigationContextMenu: NSMenu
{
	func addAction(
		title: String,
		icon: DesktopIcon,
		key: String = "",
		modifiers: NSEvent.ModifierFlags = [],
		callback: (() -> Void)?
	)
	{
		let target = ActionTarget(callback: callback)
		let item = NSMenuItem(
			title: title,
			action: #selector(ActionTarget.invoke),
			keyEquivalent: key
		)
		item.target = target
		// NSMenuItem's target is weak; retain its captured callback with the item.
		item.representedObject = target
		item.keyEquivalentModifierMask = modifiers
		item.image = DesktopIcons.image(icon)
		item.isEnabled = callback != nil
		addItem(item)
	}

	@MainActor
	private final class ActionTarget: NSObject
	{
		private let callback: (() -> Void)?

		init(callback: (() -> Void)?)
		{
			self.callback = callback
		}

		@objc func invoke()
		{
			callback?()
		}
	}
}
