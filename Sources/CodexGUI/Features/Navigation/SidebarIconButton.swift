import AppKit

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
			contentTintColor = isSearchActive ? .controlAccentColor : .secondaryLabelColor
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
			presentation: .nativeIcon
		)
		self.target = target
		self.action = action
		symbol = icon
		toolTip = label
		setAccessibilityLabel(label)
		if role == .search
		{
			toolTip = "Search"
			tooltipShortcut = "⌘K"
			tooltipPlacement = .below
			image = DesktopIcons.image(
				icon,
				size: 16
			)
			contentTintColor = AppKitColorTokens.secondaryText
		}
		let isProjectRow = role == .projectInfo || role == .projectNewChat
		if isProjectRow
		{
			image = DesktopIcons.image(
				icon,
				size: LayoutTokens.ProjectActions.actionIconSize
			)
		}
		let width: CGFloat = isProjectRow ? LayoutTokens.ProjectActions
			.actionSize : role == .refresh ? 26 : role == .search ? 28 : LayoutTokens.Sidebar
			.headingActionSize
		widthAnchor.constraint(equalToConstant: width).isActive = true
		if role != .refresh
		{
			heightAnchor.constraint(equalToConstant: width).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
