import AppKit

/// Captures row callbacks when opened so reuse cannot redirect a pending menu action.
@MainActor
final class TaskSidebarContextMenu: NavigationContextMenu
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

}
