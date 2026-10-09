import AppKit

@MainActor
final class ProjectSidebarContextMenu: NavigationContextMenu
{
	init(
		isPinned: Bool,
		onTogglePin: (() -> Void)?,
		onRename: (() -> Void)?,
		onReveal: (() -> Void)?,
		onArchive: (() -> Void)?,
		onRemove: (() -> Void)?
	)
	{
		super.init(title: "Project")
		autoenablesItems = false
		addAction(
			title: isPinned ? "Unpin" : "Pin",
			icon: .pin,
			callback: onTogglePin
		)
		addAction(
			title: "Rename",
			icon: .pencil,
			callback: onRename
		)
		addItem(.separator())
		addAction(
			title: "Reveal in Finder",
			icon: .folder,
			callback: onReveal
		)
		addItem(.separator())
		addAction(
			title: "Archive chats",
			icon: .archive,
			callback: onArchive
		)
		addItem(.separator())
		addAction(
			title: "Remove project",
			icon: .xCrossed,
			callback: onRemove
		)
	}
	required init(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}
}
