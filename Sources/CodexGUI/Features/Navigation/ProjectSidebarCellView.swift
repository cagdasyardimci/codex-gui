import AppKit

@MainActor
final class ProjectSidebarCellView: NSTableCellView
{
	var onShowInfo: ((ProjectSidebarCellView) -> Void)?
	var onNewChat: (() -> Void)?

	private let infoButton = SidebarIconButton(role: .projectInfo)
	private let newChatButton = SidebarIconButton(role: .projectNewChat)
	private let actionStack = NSStackView()
	private var isPointerInside = false
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
		])
		imageView = folder
		textField = label
		updateActions()
	}

	private func configureActions()
	{
		infoButton.target = self
		infoButton.action = #selector(showInfo)
		newChatButton.target = self
		newChatButton.action = #selector(startChat)
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
		imageView?.image = DesktopIcons.image(
			isExpanded ? .folderOpen : .folder,
			accessibilityDescription: isExpanded ?
				"Expanded project" :
				"Collapsed project"
		)
		textField?.stringValue = name
		textField?.font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		refreshTitleColor()
		textField?.toolTip = nil
		setAccessibilityLabel(isCurrent ? "Selected project \(name)" : "Open project \(name)")
		infoButton.setAccessibilityLabel("Project actions for \(name)")
		infoButton.toolTip = nil
		newChatButton.setAccessibilityLabel("Start a new conversation in project \(name)")
		newChatButton.toolTip = nil
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

	override func viewDidMoveToSuperview()
	{
		super.viewDidMoveToSuperview()
		setHovered((superview as? ConversationSidebarRowView)?.isHovered == true)
	}

	override func mouseEntered(with event: NSEvent)
	{
		setHovered(true)
	}

	override func mouseExited(with event: NSEvent)
	{
		setHovered(false)
	}

	func setHovered(_ hovered: Bool)
	{
		guard isPointerInside != hovered
		else
		{
			return
		}
		isPointerInside = hovered
		updateActions()
		layoutSubtreeIfNeeded()
	}

	private func updateActions()
	{
		actionStack.isHidden = !isPointerInside
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
