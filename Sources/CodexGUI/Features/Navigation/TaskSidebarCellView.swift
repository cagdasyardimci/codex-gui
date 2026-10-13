import AppKit

final class TaskSidebarCellView: NSTableCellView
{
	var onRename: (() -> Void)?
	var onTogglePin: (() -> Void)?
	var onMarkUnread: (() -> Void)?
	var isPinned = false
	var onArchive: (() -> Void)?
	var onDelete: (() -> Void)?
	let archiveButton = NSButton(
		title: "Archive",
		target: nil,
		action: nil
	)
	let deleteButton = NSButton(
		title: "Delete permanently",
		target: nil,
		action: nil
	)
	var hoverCard: TaskHoverCard?
	{
		willSet
		{
			hoverCard?.dismiss()
		}
	}
	let progressRing = TaskProgressRingView(frame: .zero)
	let unreadDot = NSView(frame: .zero)
	private let actions = NSStackView()
	private var hoverTrackingArea: NSTrackingArea?
	private var isHovered = false
	private var titleTrailingConstraint: NSLayoutConstraint?
	private var titleLeadingConstraint: NSLayoutConstraint?

	private typealias Layout = LayoutTokens.TaskActions

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		let label = HoverScrollingTextField(labelWithString: "")
		label.font = .systemFont(ofSize: 14)
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.cell?.usesSingleLineMode = true
		label.cell?.isScrollable = false
		label.allowsExpansionToolTips = false
		label.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		textField = label

		configureActionButtons()
		configureUnreadIndicator()
		installCellSubviews(titleField: label)
	}

	private func configureActionButtons()
	{
		archiveButton.target = self
		archiveButton.action = #selector(archiveTask)
		AppKitControlStyling.styleButton(
			archiveButton,
			icon: .archive
		)
		deleteButton.target = self
		deleteButton.action = #selector(deleteTask)
		AppKitControlStyling.styleButton(
			deleteButton,
			icon: .trash
		)
		for button in [archiveButton, deleteButton]
		{
			button.imagePosition = .imageOnly
			button.toolTip = button.title
			button.setAccessibilityLabel(button.title + " task")
			actions.addArrangedSubview(button)
			button.widthAnchor.constraint(equalToConstant: Layout.actionButtonWidth).isActive = true
			button.heightAnchor.constraint(equalToConstant: Layout.actionButtonHeight)
				.isActive = true
		}
		actions.orientation = .horizontal
		actions.spacing = Layout.actionSpacing
		actions.isHidden = true
		actions.alphaValue = 0
	}

	private func configureUnreadIndicator()
	{
		unreadDot.wantsLayer = true
		refreshUnreadColor()
		unreadDot.layer?.cornerRadius = Layout.unreadIndicatorSize / 2
		unreadDot.isHidden = true
		unreadDot.setAccessibilityElement(false)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshUnreadColor()
	}

	private func refreshUnreadColor()
	{
		// Descendants receive the inherited change after their parent callback.
		unreadDot.layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			.systemBlue,
			for: self
		)
	}

	private func installCellSubviews(titleField: NSTextField)
	{
		for child in [titleField, progressRing, unreadDot, actions]
		{
			addSubview(child)
			child.translatesAutoresizingMaskIntoConstraints = false
		}
		NSLayoutConstraint.activate([
			unreadDot.widthAnchor.constraint(equalToConstant: Layout.unreadIndicatorSize),
			unreadDot.heightAnchor.constraint(equalToConstant: Layout.unreadIndicatorSize),
			unreadDot.centerXAnchor.constraint(equalTo: progressRing.centerXAnchor),
			unreadDot.centerYAnchor.constraint(equalTo: centerYAnchor),
			progressRing.widthAnchor.constraint(equalToConstant: Layout.progressRingSize),
			progressRing.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -4
			),
			progressRing.heightAnchor.constraint(equalToConstant: Layout.progressRingSize),
			progressRing.centerYAnchor.constraint(equalTo: centerYAnchor),
			titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
			actions.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -2
			),
			actions.centerYAnchor.constraint(equalTo: centerYAnchor),
			actions.widthAnchor.constraint(
				equalToConstant: Layout.actionButtonWidth * 2 + Layout.actionSpacing
			),
		])
		let leading = titleField.leadingAnchor.constraint(
			equalTo: leadingAnchor,
			constant: 26
		)
		leading.isActive = true
		titleLeadingConstraint = leading
		updateTitleLayout()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setPinnedRow(_ pinned: Bool)
	{
		titleLeadingConstraint?.constant = pinned ? 4 : 26
	}

	func setTurnRunning(_ running: Bool)
	{
		progressRing.setRunning(running)
		updateTitleLayout()
	}

	func setUnread(_ unread: Bool)
	{
		unreadDot.isHidden = !unread
		updateTitleLayout()
	}

	func setActionsEnabled(_ enabled: Bool)
	{
		archiveButton.isEnabled = enabled
		deleteButton.isEnabled = enabled
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let hoverTrackingArea
		{
			removeTrackingArea(hoverTrackingArea)
		}
		let tracking = NSTrackingArea(
			rect: .zero,
			options: [
				.mouseEnteredAndExited,
				.activeInKeyWindow,
				.inVisibleRect
			],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(tracking)
		hoverTrackingArea = tracking
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		actions.isHidden = false
		actions.alphaValue = 1
		progressRing.alphaValue = 0
		unreadDot.alphaValue = 0
		updateTitleLayout()
		layoutSubtreeIfNeeded()
		(textField as? HoverScrollingTextField)?.setHovered(true)
		hoverCard?.show(beside: self)
	}
	override func mouseExited(with event: NSEvent)
	{
		dismissHoverCard()
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		dismissHoverCard()
		NotificationCenter.default.removeObserver(self)
		super.viewWillMove(toWindow: newWindow)
		if let newWindow
		{
			for name in [NSWindow.didResignKeyNotification,
							NSWindow.willCloseNotification,
							NSWindow.willMoveNotification,
							NSWindow.didResizeNotification]
			{
				NotificationCenter.default.addObserver(
					self,
					selector: #selector(dismissHoverCard),
					name: name,
					object: newWindow
				)
			}
			enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(dismissHoverCard),
				name: NSView.boundsDidChangeNotification,
				object: enclosingScrollView?.contentView
			)
		}
	}

	@objc private func dismissHoverCard()
	{
		isHovered = false
		hoverCard?.dismiss()
		(textField as? HoverScrollingTextField)?.setHovered(false)
		actions.isHidden = true
		actions.alphaValue = 0
		progressRing.alphaValue = 1
		unreadDot.alphaValue = 1
		updateTitleLayout()
	}

	private func updateTitleLayout()
	{
		guard let textField
		else
		{
			return
		}
		let visibleTrailingContent: NSLayoutXAxisAnchor
		if isHovered
		{
			visibleTrailingContent = actions.leadingAnchor
		}
		else if progressRing.isRunning
		{
			visibleTrailingContent = progressRing.leadingAnchor
		}
		else if !unreadDot.isHidden
		{
			visibleTrailingContent = unreadDot.leadingAnchor
		}
		else
		{
			visibleTrailingContent = trailingAnchor
		}
		titleTrailingConstraint?.isActive = false
		let constraint = textField.trailingAnchor.constraint(
			equalTo: visibleTrailingContent,
			constant: -4
		)
		constraint.isActive = true
		titleTrailingConstraint = constraint
	}

	override func menu(for event: NSEvent) -> NSMenu?
	{
		makeContextMenu()
	}

	func makeContextMenu() -> NSMenu
	{
		dismissHoverCard()
		return TaskSidebarContextMenu(
			isPinned: isPinned,
			onRename: onRename,
			onTogglePin: onTogglePin,
			onMarkUnread: onMarkUnread,
			onArchive: archiveButton.isEnabled ? onArchive : nil,
			onDelete: deleteButton.isEnabled ? onDelete : nil
		)
	}

	override func mouseDown(with event: NSEvent)
	{
		dismissHoverCard()
		super.mouseDown(with: event)
	}

	@objc private func archiveTask()
	{
		if archiveButton.isEnabled
		{
			dismissHoverCard()
			onArchive?()
		}
	}

	@objc private func deleteTask()
	{
		if deleteButton.isEnabled
		{
			dismissHoverCard()
			onDelete?()
		}
	}
}
