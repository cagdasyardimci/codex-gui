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

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		actionStack.orientation = .horizontal
		actionStack.alignment = .centerY
		actionStack.spacing = 4
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
		let label = NSTextField(labelWithString: "")
		label.font = .systemFont(
			ofSize: 14,
			weight: .regular
		)
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
				constant: 2
			),
			folder.widthAnchor.constraint(equalToConstant: 16),
			folder.heightAnchor.constraint(equalToConstant: 16),
			folder.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.leadingAnchor.constraint(
				equalTo: folder.trailingAnchor,
				constant: 8
			),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			actionStack.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -2
			),
			actionStack.centerYAnchor.constraint(equalTo: centerYAnchor),
			actionStack.widthAnchor.constraint(equalToConstant: 44),
			infoButton.widthAnchor.constraint(equalToConstant: 20),
			infoButton.heightAnchor.constraint(equalToConstant: 22),
			newChatButton.widthAnchor.constraint(equalToConstant: 20),
			newChatButton.heightAnchor.constraint(equalToConstant: 22),
		])
		imageView = folder
		textField = label
		updateActions()
	}

	private func configureActions()
	{
		infoButton.target = self
		infoButton.action = #selector(showInfo)
		DesktopTheme.styleButton(
			infoButton,
			icon: .dotsHorizontal
		)
		infoButton.imagePosition = .imageOnly

		newChatButton.target = self
		newChatButton.action = #selector(startChat)
		DesktopTheme.styleButton(
			newChatButton,
			icon: .chatCompose
		)
		newChatButton.imagePosition = .imageOnly
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
		textField?.font = .systemFont(
			ofSize: 14,
			weight: .regular
		)
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
			textField?.textColor = .labelColor.withAlphaComponent(
				NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.9
			)
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
