import AppKit

final class TaskSidebarCellView: NSTableCellView
{
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

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		let label = NSTextField(labelWithString: "")
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

		archiveButton.target = self
		archiveButton.action = #selector(archiveTask)
		DesktopTheme.styleButton(
			archiveButton,
			icon: .archive
		)
		deleteButton.target = self
		deleteButton.action = #selector(deleteTask)
		DesktopTheme.styleButton(
			deleteButton,
			icon: .trash
		)
		for button in [archiveButton, deleteButton]
		{
			button.imagePosition = .imageOnly
			button.toolTip = button.title
			button.setAccessibilityLabel(button.title + " task")
			actions.addArrangedSubview(button)
			button.widthAnchor.constraint(equalToConstant: 20).isActive = true
			button.heightAnchor.constraint(equalToConstant: 22).isActive = true
		}
		actions.orientation = .horizontal
		actions.spacing = 4
		// Keep the title's available width fixed when hover actions appear.
		actions.alphaValue = 0
		unreadDot.wantsLayer = true
		unreadDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
		unreadDot.layer?.cornerRadius = 4
		unreadDot.isHidden = true
		unreadDot.setAccessibilityElement(false)
		for child in [label, progressRing, unreadDot, actions]
		{
			addSubview(child)
			child.translatesAutoresizingMaskIntoConstraints = false
		}
		NSLayoutConstraint.activate([
			unreadDot.widthAnchor.constraint(equalToConstant: 8),
			unreadDot.heightAnchor.constraint(equalToConstant: 8),
			unreadDot.centerXAnchor.constraint(equalTo: progressRing.centerXAnchor),
			unreadDot.centerYAnchor.constraint(equalTo: centerYAnchor),
			progressRing.widthAnchor.constraint(equalToConstant: 16),
			progressRing.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -4
			),
			progressRing.heightAnchor.constraint(equalToConstant: 16),
			progressRing.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 26
			),
			label.trailingAnchor.constraint(
				equalTo: actions.leadingAnchor,
				constant: -4
			),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			actions.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -2
			),
			actions.centerYAnchor.constraint(equalTo: centerYAnchor),
			actions.widthAnchor.constraint(equalToConstant: 44),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setTurnRunning(_ running: Bool)
	{
		progressRing.setRunning(running)
	}

	func setUnread(_ unread: Bool)
	{
		unreadDot.isHidden = !unread
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
		actions.alphaValue = 1
		progressRing.alphaValue = 0
		unreadDot.alphaValue = 0
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
		hoverCard?.dismiss()
		actions.alphaValue = 0
		progressRing.alphaValue = 1
		unreadDot.alphaValue = 1
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
