import AppKit

@MainActor
final class ProjectSidebarCellView: NSTableCellView
{
	var onShowInfo: ((ProjectSidebarCellView) -> Void)?
	var onNewChat: (() -> Void)?

	private let infoButton = NSButton(
		title: "Project information",
		target: nil,
		action: nil
	)
	private let newChatButton = NSButton(
		title: "New Chat",
		target: nil,
		action: nil
	)
	private let actionStack = NSStackView()
	private var projectTrackingArea: NSTrackingArea?
	private var isPointerInside = false
	private var isCurrentProject = false
	private var titleTrailingConstraint: NSLayoutConstraint?

	private typealias Layout = LayoutTokens.ProjectActions

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		actionStack.orientation = .horizontal
		actionStack.alignment = .centerY
		actionStack.spacing = Layout.actionSpacing
		actionStack.addArrangedSubview(infoButton)
		actionStack.addArrangedSubview(newChatButton)

		let folder = makeFolderIcon()
		let label = makeProjectTitle()

		configureActions()

		installProjectCellLayout(
			folder: folder,
			label: label
		)
	}

	private func makeFolderIcon() -> NSImageView
	{
		let folder = NSImageView()
		folder.image = DesktopIcons.image(.folder)
		folder.contentTintColor = .secondaryLabelColor
		folder.setAccessibilityElement(false)

		return folder
	}

	private func makeProjectTitle() -> NSTextField
	{
		let label = SidebarTextField(labelWithString: "")
		label.font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		label.lineBreakMode = .byTruncatingTail
		label.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		label.cell?.usesSingleLineMode = true
		label.cell?.isScrollable = false
		label.allowsExpansionToolTips = false

		return label
	}

	private func installProjectCellLayout(
		folder: NSImageView,
		label: NSTextField
	)
	{
		for child in [folder, label, actionStack]
		{
			addSubview(child)
			child.translatesAutoresizingMaskIntoConstraints = false
		}

		NSLayoutConstraint.activate([
			folder.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: NavigationSidebarLayout.cellInset
			),
			folder.widthAnchor.constraint(equalToConstant: NavigationSidebarLayout.iconSize),
			folder.heightAnchor.constraint(equalToConstant: NavigationSidebarLayout.iconSize),
			folder.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.leadingAnchor.constraint(
				equalTo: folder.trailingAnchor,
				constant: NavigationSidebarLayout.iconTextSpacing
			),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			actionStack.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -NavigationSidebarLayout.cellInset
			),
			actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			actionStack.widthAnchor.constraint(equalToConstant: Layout.actionWidth),
			infoButton.widthAnchor.constraint(equalToConstant: Layout.actionSize),
			infoButton.heightAnchor.constraint(equalToConstant: Layout.actionSize),
			newChatButton.widthAnchor.constraint(equalToConstant: Layout.actionSize),
			newChatButton.heightAnchor.constraint(equalToConstant: Layout.actionSize),
		])
		imageView = folder
		textField = label
		updateActions()
	}

	private func configureActions()
	{
		infoButton.target = self
		infoButton.action = #selector(showInfo)
		AppKitControlStyling.styleButton(
			infoButton,
			icon: .dotsHorizontal
		)
		infoButton.imagePosition = .imageOnly

		newChatButton.target = self
		newChatButton.action = #selector(startChat)
		AppKitControlStyling.styleButton(
			newChatButton,
			icon: .chatCompose
		)
		newChatButton.imagePosition = .imageOnly
		infoButton.image = DesktopIcons.image(
			.dotsHorizontal,
			size: Layout.actionIconSize
		)
		newChatButton.image = DesktopIcons.image(
			.chatCompose,
			size: Layout.actionIconSize
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		project: URL,
		name: String,
		isCurrent: Bool,
		isExpanded: Bool = false,
		isPinned: Bool,
		canStartChat: Bool
	)
	{
		isCurrentProject = isCurrent
		imageView?.image = DesktopIcons.image(
			isExpanded ? .folderOpen : .folder,
			accessibilityDescription: isExpanded ?
				"Expanded project" :
				"Collapsed project"
		)
		textField?.stringValue = name
		textField?.font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		refreshTitleColor()
		toolTip = (isPinned ? "Pinned project\n" : "") + project.path
		setAccessibilityLabel(isCurrent ? "Selected project \(name)" : "Open project \(name)")
		infoButton.setAccessibilityLabel("Project actions for \(name)")
		infoButton.toolTip = "Project actions"
		newChatButton.setAccessibilityLabel("Start a new conversation in project \(name)")
		newChatButton.toolTip = "New Chat in \(name)"
		newChatButton.isEnabled = canStartChat
		updateActions()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshTitleColor()
	}

	private func refreshTitleColor()
	{
		// The label can still have its previous appearance during the cell's appearance callback.
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			textField?.textColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
				? AppKitColorTokens.primaryText : AppKitColorTokens.sidebarText
		}
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let projectTrackingArea
		{
			removeTrackingArea(projectTrackingArea)
		}
		let tracking = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(tracking)
		projectTrackingArea = tracking
	}

	override func mouseEntered(with event: NSEvent)
	{
		isPointerInside = true
		updateActions()
	}

	override func mouseExited(with event: NSEvent)
	{
		isPointerInside = false
		updateActions()
	}

	private func updateActions()
	{
		actionStack.isHidden = !isCurrentProject && !isPointerInside
		guard let textField
		else
		{
			return
		}
		titleTrailingConstraint?.isActive = false
		let constraint = textField.trailingAnchor.constraint(
			equalTo: actionStack.isHidden ? trailingAnchor : actionStack.leadingAnchor,
			constant: -4
		)
		constraint.isActive = true
		titleTrailingConstraint = constraint
	}
	@objc private func showInfo()
	{
		onShowInfo?(self)
	}
	@objc private func startChat()
	{
		if newChatButton.isEnabled
		{
			onNewChat?()
		}
	}
}
