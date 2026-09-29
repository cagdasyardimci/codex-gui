import AppKit

@MainActor
final class ProjectInfoPopoverView: NSView
{
	var onTogglePin: (() -> Void)?
	var onEditProject: (() -> Void)?

	private let nameLabel = NSTextField(labelWithString: "")
	private let countLabel = NSTextField(labelWithString: "")
	private let pathLabel = NSTextField(labelWithString: "")
	private let pinButton = NSButton(
		title: "Pin project",
		target: nil,
		action: nil
	)
	private let editButton = NSButton(
		title: "Edit project",
		target: nil,
		action: nil
	)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		configureLabels()
		configureActions()

		let header = AppKitLayout.horizontalStack(
			[icon("folder"), nameLabel, NSView(), pinButton],
			spacing: 7
		)
		let counts = AppKitLayout.horizontalStack(
			[icon("bubble.left"), countLabel],
			spacing: 7
		)
		let path = AppKitLayout.horizontalStack(
			[icon("folder"), pathLabel],
			spacing: 7
		)
		let topSeparator = separator()
		let bottomSeparator = separator()
		let stack = AppKitLayout.verticalStack(
			[header, counts, topSeparator, path, bottomSeparator, editButton],
			spacing: 7
		)
		let surface = DesktopSurface(
			DesktopTheme.selection,
			cornerRadius: 10
		)
		AppKitLayout.pin(
			surface,
			to: self,
			inset: 0
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 10
		)
		for row in [header, counts, topSeparator, path, bottomSeparator, editButton]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		pinButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
		pinButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
		widthAnchor.constraint(equalToConstant: 300).isActive = true
	}

	private func configureLabels()
	{
		nameLabel.font = .systemFont(
			ofSize: 13,
			weight: .semibold
		)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		countLabel.font = .systemFont(ofSize: 12)

		pathLabel.font = .systemFont(ofSize: 12)
		pathLabel.lineBreakMode = .byTruncatingMiddle
		pathLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	private func configureActions()
	{
		pinButton.target = self
		pinButton.action = #selector(togglePin)
		pinButton.setButtonType(.toggle)
		DesktopTheme.styleButton(
			pinButton,
			symbol: "pin"
		)
		pinButton.imagePosition = .imageOnly

		editButton.target = self
		editButton.action = #selector(editProject)
		DesktopTheme.styleButton(
			editButton,
			symbol: "gearshape"
		)
		editButton.font = .systemFont(ofSize: 12)
		editButton.alignment = .left
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		project: URL,
		name: String,
		isPinned: Bool,
		loadedTaskCount: Int?,
		activeTaskCount: Int?
	)
	{
		nameLabel.stringValue = name
		nameLabel.setAccessibilityLabel("Project \(name)")

		renderPinState(
			isPinned: isPinned,
			name: name
		)
		renderTaskCounts(
			loadedTaskCount: loadedTaskCount,
			activeTaskCount: activeTaskCount
		)

		pathLabel.stringValue = (project.path as NSString).abbreviatingWithTildeInPath
		pathLabel.toolTip = project.path
		pathLabel.setAccessibilityLabel("Project path \(project.path)")
		editButton.setAccessibilityLabel("Edit local display name for project \(name)")
	}

	private func renderPinState(
		isPinned: Bool,
		name: String
	)
	{
		pinButton.state = isPinned ? .on : .off
		pinButton.image = NSImage(
			systemSymbolName: isPinned ? "pin.fill" : "pin",
			accessibilityDescription: nil
		)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 13,
				weight: .regular
			))
		pinButton.setAccessibilityLabel(isPinned ? "Unpin project \(name)" : "Pin project \(name)")
		pinButton.toolTip = isPinned ? "Unpin project" : "Pin project"
	}

	private func renderTaskCounts(
		loadedTaskCount: Int?,
		activeTaskCount: Int?
	)
	{
		let tasks = loadedTaskCount.map
		{
			String($0)
		} ?? "—"
		let active = activeTaskCount.map
		{
			String($0)
		} ?? "—"
		countLabel.stringValue =
			"\(tasks) \(loadedTaskCount == 1 ? "task" : "tasks") · \(active) active"
		countLabel.toolTip =
			loadedTaskCount == nil
				? "This project's conversation history and active-task count are not loaded."
				: "Counts cover this checkout's loaded conversations and current active task. The "
				+ "archive filter and unloaded history can change the available conversation count."
		countLabel.setAccessibilityLabel("\(countLabel.stringValue). \(countLabel.toolTip ?? "")")
	}

	private func icon(_ symbol: String) -> NSImageView
	{
		let image = NSImageView()
		image.image = NSImage(
			systemSymbolName: symbol,
			accessibilityDescription: nil
		)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(
				pointSize: 13,
				weight: .regular
			))
		image.contentTintColor = .secondaryLabelColor
		image.setAccessibilityElement(false)
		image.widthAnchor.constraint(equalToConstant: 14).isActive = true
		image.heightAnchor.constraint(equalToConstant: 16).isActive = true
		return image
	}

	private func separator() -> NSView
	{
		let line = NSBox()
		line.boxType = .separator
		line.heightAnchor.constraint(equalToConstant: 1).isActive = true
		return line
	}

	@objc private func togglePin()
	{
		onTogglePin?()
	}
	@objc private func editProject()
	{
		onEditProject?()
	}
}

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

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		actionStack.orientation = .horizontal
		actionStack.alignment = .centerY
		actionStack.spacing = 4
		actionStack.addArrangedSubview(infoButton)
		actionStack.addArrangedSubview(newChatButton)

		let folder = NSImageView()
		folder.image = NSImage(
			systemSymbolName: "folder",
			accessibilityDescription: nil
		)
		folder.contentTintColor = .secondaryLabelColor
		folder.setAccessibilityElement(false)

		let label = NSTextField(labelWithString: "")
		label.font = .systemFont(
			ofSize: 14,
			weight: .regular
		)
		label.lineBreakMode = .byTruncatingTail

		configureActions()

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
			label.trailingAnchor.constraint(
				equalTo: actionStack.leadingAnchor,
				constant: -4
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
	}

	private func configureActions()
	{
		infoButton.target = self
		infoButton.action = #selector(showInfo)
		DesktopTheme.styleButton(
			infoButton,
			symbol: "ellipsis"
		)
		infoButton.imagePosition = .imageOnly

		newChatButton.target = self
		newChatButton.action = #selector(startChat)
		DesktopTheme.styleButton(
			newChatButton,
			symbol: "square.and.pencil"
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
		isPinned: Bool,
		canStartChat: Bool
	)
	{
		isCurrentProject = isCurrent
		textField?.stringValue = name
		textField?.font = .systemFont(
			ofSize: 14,
			weight: .regular
		)
		textField?.textColor = .labelColor.withAlphaComponent(
			NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.9
		)
		toolTip = (isPinned ? "Pinned project\n" : "") + project.path
		setAccessibilityLabel(isCurrent ? "Selected project \(name)" : "Open project \(name)")
		infoButton.setAccessibilityLabel("Show information for project \(name)")
		infoButton.toolTip = "Project information"
		newChatButton.setAccessibilityLabel("Start a new conversation in project \(name)")
		newChatButton.toolTip = "New Chat in \(name)"
		newChatButton.isEnabled = canStartChat
		updateActions()
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
