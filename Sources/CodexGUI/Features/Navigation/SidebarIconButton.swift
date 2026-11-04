import AppKit

/// Supplies sidebar actions; the shared button owns their rendering and focus states.
@MainActor
final class SidebarIconButton: DesktopStyledButton
{
	enum Role
	{
		case refresh, search, options, add, projectInfo, projectNewChat
	}

	var isSearchActive = false
	{
		didSet
		{
			state = isSearchActive ? .on : .off
		}
	}

	init(
		role: Role,
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		let title: String
		let icon: DesktopIcon
		let label: String
		switch role
		{
		case .refresh:
			title = "Refresh"
			icon = .arrowRotateCw
			label = "Refresh conversations"
		case .search:
			title = "Search"
			icon = .search
			label = "Search conversation titles and previews"
		case .options:
			title = ""
			icon = .dotsHorizontal
			label = "Organize sidebar and sort chats"
		case .add:
			title = "Project Actions"
			icon = .plus
			label = "Add new project"
		case .projectInfo:
			title = "Project information"
			icon = .dotsHorizontal
			label = title
		case .projectNewChat:
			title = "New Chat"
			icon = .composeEditSquare
			label = title
		}
		super.init(
			title: title,
			presentation: role == .search ? .searchIcon : .sidebarIcon,
			size: role == .projectInfo || role == .projectNewChat ? .mini : .small
		)
		self.target = target
		self.action = action
		symbol = icon
		toolTip = label
		setAccessibilityLabel(label)
		if role == .search
		{
			keyboardFocusPolicy = .dialog
			toolTip = "Search"
			tooltipShortcut = "⌘K"
			tooltipPlacement = .below
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
