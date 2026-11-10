import AppKit

@MainActor
final class ProjectInfoPopoverView: NSView
{
	var onTogglePin: (() -> Void)?
	var onEditProject: (() -> Void)?
	var onOpenProject: (() -> Void)?

	private let nameLabel = NSTextField(labelWithString: "")
	private let countLabel = NSTextField(labelWithString: "")
	private let pathButton = DesktopPreviewActionRow(
		icon: .folder,
		showsIndicator: true
	)
	private let pinButton = DesktopIconButton(
		title: "Pin project",
		label: "Pin project",
		icon: .pin,
		size: .small
	)
	private let editButton = DesktopPreviewActionRow(icon: .settings)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		configureLabels()
		configureActions()

		installProjectInfoLayout()
	}

	private func installProjectInfoLayout()
	{
		let header = AppKitLayout.horizontalStack(
			[icon(
				.folder,
				primary: true
			), nameLabel, NSView(), pinButton],
			spacing: 6
		)
		let counts = AppKitLayout.horizontalStack(
			[icon(.chat), countLabel],
			spacing: 6
		)
		let path = pathButton
		let edit = editButton
		let topSeparator = separator()
		let bottomSeparator = separator()
		let stack = AppKitLayout.verticalStack(
			[header, counts, topSeparator, path, bottomSeparator, edit],
			spacing: 6
		)
		// The hover card or native popover owns the surrounding surface and padding.
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 0
		)
		for row in [header, counts, topSeparator, path, bottomSeparator, edit]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		widthAnchor.constraint(equalToConstant: 304).isActive = true
	}

	private func configureLabels()
	{
		nameLabel.setTypographyRole(TypographyTokens.Text.title)
		nameLabel.textColor = AppKitColorTokens.primaryText
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		countLabel.setTypographyRole(TypographyTokens.Text.detail)
		countLabel.textColor = AppKitColorTokens.primaryText
	}

	private func configureActions()
	{
		pinButton.target = self
		pinButton.action = #selector(togglePin)
		pinButton.setButtonType(.toggle)
		pathButton.target = self
		pathButton.action = #selector(openProject)

		editButton.target = self
		editButton.action = #selector(editProject)
		editButton.setText("Edit project")
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

		pathButton.setText((project.path as NSString).abbreviatingWithTildeInPath)
		pathButton.setAccessibilityLabel("Open \(project.path) in Finder")
		editButton.setAccessibilityLabel("Edit project \(name)")
	}

	private func renderPinState(
		isPinned: Bool,
		name: String
	)
	{
		pinButton.state = isPinned ? .on : .off
		pinButton.image = DesktopIcons.image(
			isPinned ? .pinFilled : .pin,
			size: 13
		)
		pinButton.setLabel(
			isPinned ? "Unpin project \(name)" : "Pin project \(name)",
			toolTip: isPinned ? "Unpin project" : "Pin project"
		)
	}

	private func renderTaskCounts(
		loadedTaskCount: Int?,
		activeTaskCount: Int?
	)
	{
		var parts: [String] = []
		if let loadedTaskCount
		{
			parts.append("\(loadedTaskCount) \(loadedTaskCount == 1 ? "chat" : "chats")")
		}
		if let activeTaskCount, activeTaskCount > 0
		{
			parts.append("\(activeTaskCount) active")
		}
		countLabel.superview?.isHidden = parts.isEmpty
		countLabel.stringValue = parts.joined(separator: " · ")
		countLabel.setAccessibilityLabel(countLabel.stringValue)
	}

	private func icon(
		_ symbol: DesktopIcon,
		primary: Bool = false
	) -> NSImageView
	{
		let image = NSImageView()
		image.image = DesktopIcons.image(
			symbol,
			size: 16
		)
		image.contentTintColor = primary ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
		image.setAccessibilityElement(false)
		image.widthAnchor.constraint(equalToConstant: 16).isActive = true
		image.heightAnchor.constraint(equalToConstant: 20).isActive = true
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
	@objc private func openProject()
	{
		onOpenProject?()
	}
	@objc private func editProject()
	{
		onEditProject?()
	}
}
