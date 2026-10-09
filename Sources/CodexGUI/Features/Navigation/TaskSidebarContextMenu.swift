import AppKit

/// Captures row callbacks when opened so reuse cannot redirect a pending menu action.
@MainActor
final class TaskSidebarContextMenu: NSMenu
{
	init(
		isPinned: Bool,
		onRename: (() -> Void)?,
		onTogglePin: (() -> Void)?,
		onMarkUnread: (() -> Void)?,
		onArchive: (() -> Void)?,
		onDelete: (() -> Void)?
	)
	{
		super.init(title: "Task")
		autoenablesItems = false
		addAction(
			title: "Rename",
			icon: .pencil,
			key: "r",
			modifiers: [.option, .command],
			callback: onRename
		)
		addAction(
			title: isPinned ? "Unpin" : "Pin",
			icon: .pin,
			key: "p",
			modifiers: [.option, .command],
			callback: onTogglePin
		)
		addAction(
			title: "Mark as unread",
			icon: .eye,
			key: "u",
			modifiers: [.shift, .command],
			callback: onMarkUnread
		)
		addItem(.separator())
		addAction(
			title: "Archive",
			icon: .archive,
			key: "a",
			modifiers: [.shift, .command],
			callback: onArchive
		)
		addAction(
			title: "Permanently delete",
			icon: .trash,
			callback: onDelete
		)
	}

	required init(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	private func addAction(
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
