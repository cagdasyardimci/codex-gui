import AppKit

@MainActor
final class ProjectInfoPopoverView: NSView
{
	var onTogglePin: (() -> Void)?
	var onEditProject: (() -> Void)?
	var onOpenProject: (() -> Void)?

	private let nameLabel = NSTextField(labelWithString: "")
	private let countLabel = NSTextField(labelWithString: "")
	private let pathLabel = NSTextField(labelWithString: "")
	private lazy var pathButton = ProjectPathButton(label: pathLabel)
	private let pinButton = DesktopNativeIconButton(
		title: "Pin project",
		label: "Pin project",
		icon: .pin,
		size: .small
	)
	private let editButton = DesktopStyledButton(
		title: "Edit project",
		target: nil,
		action: nil
	)

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
			[icon(.folder), nameLabel, NSView(), pinButton],
			spacing: 7
		)
		let counts = AppKitLayout.horizontalStack(
			[icon(.chat), countLabel],
			spacing: 7
		)
		let path = pathButton
		let edit = AppKitLayout.horizontalStack(
			[icon(.settings), editButton],
			spacing: 7
		)
		let topSeparator = separator()
		let bottomSeparator = separator()
		let stack = AppKitLayout.verticalStack(
			[header, counts, topSeparator, path, bottomSeparator, edit],
			spacing: 7
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
		widthAnchor.constraint(equalToConstant: 300).isActive = true
	}

	private func configureLabels()
	{
		nameLabel.font = .systemFont(ofSize: 14)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)

		countLabel.font = .systemFont(ofSize: 14)

		pathLabel.font = .systemFont(ofSize: 14)
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
		pathButton.target = self
		pathButton.action = #selector(openProject)

		editButton.target = self
		editButton.action = #selector(editProject)
		editButton.font = .systemFont(ofSize: 14)
		editButton.contentTintColor = .labelColor
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
		pathButton.setAccessibilityLabel("Open \(project.path) in Finder")
		editButton.setAccessibilityLabel("Edit local display name for project \(name)")
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

	private func icon(_ symbol: DesktopIcon) -> NSImageView
	{
		let image = NSImageView()
		image.image = DesktopIcons.image(
			symbol,
			size: 14
		)
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
	@objc private func openProject()
	{
		onOpenProject?()
	}
	@objc private func editProject()
	{
		onEditProject?()
	}
}

@MainActor
private final class ProjectPathButton: DesktopHoverButton
{
	private let openIndicator = NSImageView()

	override var hoverTrackingOptions: NSTrackingArea.Options
	{
		[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
	}

	init(label: NSTextField)
	{
		super.init(frame: .zero)
		title = ""
		isBordered = false
		cornerRadius = 4
		let folder = NSImageView()
		folder.image = DesktopIcons.image(
			.folder,
			size: 14
		)
		openIndicator.image = NSImage(
			systemSymbolName: "arrow.up.right",
			accessibilityDescription: nil
		)
		for image in [folder, openIndicator]
		{
			image.contentTintColor = .secondaryLabelColor
			image.setAccessibilityElement(false)
			image.widthAnchor.constraint(equalToConstant: 14).isActive = true
			image.heightAnchor.constraint(equalToConstant: 16).isActive = true
		}
		label.setAccessibilityElement(false)
		openIndicator.alphaValue = 0
		let content = AppKitLayout.horizontalStack(
			[folder, label, openIndicator],
			spacing: 7
		)
		AppKitLayout.pin(
			content,
			to: self,
			inset: 0
		)
		heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		super.hitTest(point) == nil ? nil : self
	}

	override func hoverDidChange()
	{
		super.hoverDidChange()
		openIndicator.alphaValue = isHovered ? 1 : 0
	}
}
