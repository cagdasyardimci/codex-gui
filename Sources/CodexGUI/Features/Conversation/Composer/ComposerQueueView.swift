import AppKit

@MainActor
final class ComposerQueueView: NSView
{
	static let composerOverlap: CGFloat = 20
	static let composerInset: CGFloat = 13
	private let scroll = NSScrollView()
	let rows = AppKitLayout.verticalStack(
		[],
		spacing: 1
	)
	let pauseLabel = DesktopTextField(labelWithString: "")
	private let pauseIcon = NSImageView(image: DesktopIcons.image(
		.pauseSm,
		size: 14
	))
	let headerDivider = DesktopSurface(AppKitColorTokens.composerQueueDivider)
	private var panelHeight: NSLayoutConstraint!
	private(set) var presentation: ConversationPresentation.Composer?
	var reorderSession: ComposerQueueDragSession?
	var reorderSettlingTask: Task<Void, Never>?
	var pendingVisualOrder: [UUID]?
	private var menuActions: [() -> Void] = []
	private(set) var queueMenu: ComposerQueueMenu?
	var onResume: (() -> Void)?
	let resumeButton = ComposerQueueTextButton(
		title: "Resume",
		icon: .playSm,
		width: 85,
		imageVerticalOffset: 1
	)
	var onRemove: ((UUID) -> Void)?
	var onSteer: ((UUID) -> Void)?
	var onReorder: (([UUID]) -> Void)?
	var onEdit: ((QueuedComposerMessage) -> Void)?
	var onSetQueueingEnabled: ((Bool) -> Void)?

	init()
	{
		super.init(frame: .zero)
		scroll.drawsBackground = false
		scroll.contentView.drawsBackground = false
		wantsLayer = true
		layer?.cornerRadius = 20
		layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
		layer?.borderWidth = 1
		layer?.masksToBounds = true
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		AppKitLayout.pin(
			scroll,
			to: self,
			inset: 0
		)
		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = 1

		rows.edgeInsets = NSEdgeInsets(
			top: 1,
			left: 1,
			bottom: Self.composerOverlap + 4,
			right: 1
		)
		scroll.documentView = rows
		rows.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
			rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
			rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
		])
		panelHeight = heightAnchor.constraint(equalToConstant: 0)
		panelHeight.isActive = true
		resumeButton
			.onHover =
			{
				[weak self, weak resumeButton] in
				self?.clearActionHovers(except: resumeButton)
			}
		resumeButton.target = self
		resumeButton.action = #selector(resumeQueue)
		resumeButton.setAccessibilityLabel("Resume")
		resumeButton.setAccessibilityIdentifier("queue-resume")
		pauseIcon.contentTintColor = AppKitColorTokens.composerQueueLeadingGlyph
		pauseIcon.setAccessibilityElement(false)
		pauseIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
		pauseIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
		pauseLabel.font = .systemFont(ofSize: 14)
		pauseLabel.textColor = AppKitColorTokens.composerSecondaryText
		pauseLabel.lineBreakMode = .byTruncatingTail
		pauseLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		pauseLabel.maximumNumberOfLines = 1
		headerDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
		refreshAppearance()
	}

	required init?(coder: NSCoder)
	{
		nil
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshAppearance()
	}
	private func refreshAppearance()
	{
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.composerQueue,
			for: self
		)
		layer?.borderColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.composerControlDivider,
			for: self
		)
	}

	func render(_ presentation: ConversationPresentation.Composer)
	{
		if let session = reorderSession,
			self.presentation?.owner == presentation.owner,
			self.presentation?.queuePaused == presentation.queuePaused,
			presentation.queuedMessages.map(\.id) == session.originalIDs,
			presentation.reservedQueuedMessageIDs.isEmpty
		{
			self.presentation = presentation
			return
		}
		cancelReordering()
		queueMenu?.close()
		if self.presentation?.owner != presentation.owner
		{
			pendingVisualOrder = nil
		}
		self.presentation = presentation
		for row in rows.arrangedSubviews
		{
			rows.removeArrangedSubview(row)
			row.removeFromSuperview()
		}
		isHidden = presentation.queuedMessages.isEmpty
		let count = CGFloat(min(
			presentation.queuedMessages.count,
			3
		))
		let paused = presentation.queuePaused
		let headerCount: CGFloat = paused ? 1 : 0
		panelHeight.constant = rows.edgeInsets.top + rows.edgeInsets.bottom
			+ count * ComposerQueueRow.rowHeight + headerCount * 34
			+ max(
				0,
				count + headerCount - 1
			) * rows.spacing
		if paused
		{
			let header = NSView()
			rows.addArrangedSubview(header)
			header.translatesAutoresizingMaskIntoConstraints = false
			header.addSubview(resumeButton)
			header.addSubview(pauseIcon)
			header.addSubview(pauseLabel)
			pauseIcon.translatesAutoresizingMaskIntoConstraints = false
			pauseLabel.translatesAutoresizingMaskIntoConstraints = false
			pauseLabel.stringValue = presentation.queueInterrupted ?
				"Queue paused because you interrupted" : "Queue paused"
			header.addSubview(headerDivider)
			headerDivider.setAccessibilityElement(false)
			headerDivider.translatesAutoresizingMaskIntoConstraints = false
			resumeButton.translatesAutoresizingMaskIntoConstraints = false
			resumeButton.isEnabled = presentation.canResumeQueue
			NSLayoutConstraint.activate([
				pauseIcon.leadingAnchor.constraint(
					equalTo: header.leadingAnchor,
					constant: 10
				),
				pauseIcon.centerYAnchor.constraint(
					equalTo: header.centerYAnchor,
					constant: 1
				),
				pauseLabel.leadingAnchor.constraint(
					equalTo: header.leadingAnchor,
					constant: 32
				),
				pauseLabel.trailingAnchor.constraint(
					equalTo: resumeButton.leadingAnchor,
					constant: -8
				),
				pauseLabel.centerYAnchor.constraint(
					equalTo: header.centerYAnchor,
					constant: 1
				),
				headerDivider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
				headerDivider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
				headerDivider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
				header.widthAnchor.constraint(
					equalTo: rows.widthAnchor,
					constant: -2
				),
				header.heightAnchor.constraint(equalToConstant: 34),
				resumeButton.trailingAnchor.constraint(
					equalTo: header.trailingAnchor,
					constant: -10
				),
				resumeButton.centerYAnchor.constraint(
					equalTo: header.centerYAnchor,
					constant: 1
				),
			])
		}
		let remove = onRemove
		let steer = onSteer
		var messages = presentation.queuedMessages
		if let order = pendingVisualOrder
		{
			if order == messages.map(\.id) || presentation.reservedQueuedMessageIDs
				.isEmpty || Set(order) != Set(messages.map(\.id))
			{
				pendingVisualOrder = nil
			}
			else
			{
				messages = ComposerQueueOrdering.reordered(
					messages,
					by: order
				)
			}
		}
		for message in messages
		{
			let row = ComposerQueueRow(message: message)
			row.queueView = self
			for button in [row.preview, row.steer, row.remove, row.overflow]
			{
				button
					.onHover =
					{
						[weak self, weak button] in
						self?.clearActionHovers(except: button)
					}
			}
			let reserved = presentation.reservedQueuedMessageIDs.contains(message.id)
			row.canDrag = !reserved && presentation.reservedQueuedMessageIDs.isEmpty
			let active = presentation.activeExecutionState?.isBusy == true
			row.steer.isHidden = !active && !paused
			row.steer
				.isEnabled = !reserved &&
				(presentation.canSteerQueuedMessage || presentation.canResumeQueue)
			row.remove.isEnabled = !reserved
			row.onSteer =
			{
				steer?(message.id)
			}
			row.onRemove =
			{
				remove?(message.id)
			}
			row.onMenu =
			{
				[weak self] button in self?.showActions(
					for: message,
					anchor: button
				)
			}
			rows.addArrangedSubview(row)
			row.widthAnchor.constraint(
				equalTo: rows.widthAnchor,
				constant: -(rows.edgeInsets.left + rows.edgeInsets.right)
			).isActive = true
		}
	}

	@objc private func resumeQueue()
	{
		onResume?()
	}

	var messageRows: [ComposerQueueRow]
	{
		rows.arrangedSubviews.compactMap
		{
			$0 as? ComposerQueueRow
		}
	}

	func actionsMenu(for message: QueuedComposerMessage) -> NSMenu
	{
		let menu = NSMenu()
		menu.autoenablesItems = false

		let beginEdit = onEdit
		let toggle = onSetQueueingEnabled
		let enabled = presentation?.queueingEnabled ?? true
		menuActions = [
			{
				beginEdit?(message)
			},
			{
				toggle?(!enabled)
			}
		]

		let edit = NSMenuItem(
			title: "Edit message",
			action: #selector(invokeMenuAction(_:)),
			keyEquivalent: ""
		)
		edit.target = self
		edit.tag = 0
		edit.isEnabled = canEdit(message)
		edit.image = DesktopIcons.image(
			.pencil,
			size: 16
		)
		menu.addItem(edit)
		let sideChat = NSMenuItem(
			title: "Open in side chat",
			action: nil,
			keyEquivalent: ""
		)
		sideChat.isEnabled = false
		sideChat.image = DesktopIcons.image(
			.chatCompose,
			size: 16
		)
		menu.addItem(sideChat)
		let queueing = NSMenuItem(
			title: enabled ? "Turn off queueing" : "Turn on queueing",
			action: #selector(invokeMenuAction(_:)),
			keyEquivalent: ""
		)
		queueing.tag = 1
		queueing.target = self
		queueing.image = DesktopIcons.image(
			.followup,
			size: 16
		)
		menu.addItem(queueing)
		return menu
	}

	private func showActions(
		for message: QueuedComposerMessage,
		anchor: NSButton
	)
	{
		queueMenu?.close()
		clearActionHovers()
		let menu = ComposerQueueMenu(
			menu: actionsMenu(for: message),
			backingScale: anchor.window?.backingScaleFactor ?? 1
		)
		queueMenu = menu
		let button = anchor as? ComposerQueueTextButton
		button?.menuIsOpen = true
		menu.onClose =
		{
			[weak self, weak button] in
			button?.menuIsOpen = false
			self?.clearActionHovers()
		}
		menu.show(from: anchor)
	}
	@objc private func invokeMenuAction(_ sender: NSMenuItem)
	{
		guard menuActions.indices.contains(sender.tag)
		else
		{
			return
		}
		menuActions[sender.tag]()
	}

	func clearActionHovers(except button: ComposerQueueTextButton? = nil)
	{
		if button == nil
		{
			clearRowHovers()
		}
		let buttons = [resumeButton] + messageRows.flatMap
		{
			[
				$0.preview,
				$0.steer,
				$0.remove,
				$0.overflow
			]
		}
		buttons.filter
		{
			$0 !== button
		}.forEach
		{
			$0.clearHover()
		}
	}

	func clearRowHovers(except row: ComposerQueueRow? = nil)
	{
		messageRows.filter
		{
			$0 !== row
		}.forEach
		{
			$0.clearHover()
		}
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			cancelReordering()
			queueMenu?.close(); clearActionHovers()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	@discardableResult
	func moveMessage(
		_ id: UUID,
		to insertionIndex: Int
	) -> Bool
	{
		guard let presentation, presentation.reservedQueuedMessageIDs.isEmpty
		else
		{
			return false
		}
		var ids = presentation.queuedMessages.map(\.id)
		guard let source = ids.firstIndex(of: id),
				(0 ... ids.count).contains(insertionIndex)
		else
		{
			return false
		}
		ids.remove(at: source)
		ids.insert(
			id,
			at: min(
				ids.count,
				insertionIndex > source ? insertionIndex - 1 : insertionIndex
			)
		)
		onReorder?(ids)
		return true
	}
}

extension ComposerQueueView
{
	private func canEdit(_ message: QueuedComposerMessage) -> Bool
	{
		guard let presentation
		else
		{
			return false
		}
		return presentation.draft.isEmpty && presentation.draftContext.isEmpty && !presentation
			.isEditingQueuedMessage
			&& !presentation.reservedQueuedMessageIDs.contains(message.id)
	}

}
