import AppKit

@MainActor
final class ComposerQueueRow: NSView
{
	static let rowHeight: CGFloat = 32
	static let leadingInset: CGFloat = 10

	let message: QueuedComposerMessage
	weak var queueView: ComposerQueueView?
	let preview: ComposerQueueTextButton
	let steer: ComposerQueueTextButton
	let remove: ComposerQueueTextButton
	let overflow: ComposerQueueTextButton
	var onSteer: (() -> Void)?
	var onRemove: (() -> Void)?
	var onMenu: ((NSButton) -> Void)?
	var canDrag = true
	{
		didSet
		{
			updateGripVisibility()
		}
	}
	private let grip = QueueDragHandle()
	private var hoverArea: NSTrackingArea?
	private var isHovered = false
	{
		didSet
		{
			updateGripVisibility()
		}
	}

	init(message: QueuedComposerMessage)
	{
		self.message = message
		preview = ComposerQueueTextButton(
			title: message.text.isEmpty ? message.context.map(\.title)
				.joined(separator: ", ") : message.text,
			presentation: .preview
		)
		steer = ComposerQueueTextButton(
			title: "Steer",
			icon: .arrowCurvedRight
		)
		remove = ComposerQueueTextButton(icon: .trash)
		overflow = ComposerQueueTextButton(icon: .dotsHorizontal)
		super.init(frame: .zero)
		wantsLayer = true
		let handle = QueueDragHandle(image: DesktopIcons.image(
			.followup,
			size: 14
		))
		handle.owner = self
		handle.contentTintColor = AppKitColorTokens.composerQueueLeadingGlyph
		handle.setAccessibilityLabel("Drag queued message")
		for button in [preview, steer, remove, overflow]
		{
			button.target = self
		}
		preview.target = nil
		steer.action = #selector(steerMessage)
		steer.hoverTooltipText = "Submit without interrupting the model"
		remove.action = #selector(removeMessage)
		overflow.action = #selector(showMenu)
		remove.setAccessibilityLabel("Delete queued message")
		overflow.setAccessibilityLabel("Queued message actions")
		preview.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		preview.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		let actions = AppKitLayout.horizontalStack(
			[steer, remove, overflow],
			spacing: 4
		)
		let stack = AppKitLayout.horizontalStack(
			[handle, preview, actions],
			spacing: 8
		)
		stack.distribution = .fill
		addSubview(stack)
		stack.translatesAutoresizingMaskIntoConstraints = false
		actions.widthAnchor.constraint(
			equalTo: steer.widthAnchor,
			constant: 56
		).isActive = true
		actions.heightAnchor.constraint(equalToConstant: ComposerQueueTextButton.actionHeight)
			.isActive = true
		grip.owner = self
		grip.setAccessibilityElement(false)
		grip.image = Self.gripArtwork
		grip.contentTintColor = AppKitColorTokens.composerQueueLeadingGlyph
		grip.alphaValue = 0
		addSubview(grip)
		grip.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			grip.leadingAnchor.constraint(equalTo: leadingAnchor),
			grip.centerYAnchor.constraint(equalTo: centerYAnchor),
			grip.widthAnchor.constraint(equalToConstant: 14),
			grip.heightAnchor.constraint(equalToConstant: 14),
		])
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: Self.leadingInset
			),
			stack.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -10
			),
			stack.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 2
			),
			stack.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -2
			),
			handle.widthAnchor.constraint(equalToConstant: 14),
			handle.heightAnchor.constraint(equalToConstant: 16),
			heightAnchor.constraint(equalToConstant: Self.rowHeight),
			preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}
	@objc private func steerMessage()
	{
		onSteer?()
	}
	@objc private func removeMessage()
	{
		onRemove?()
	}
	@objc private func showMenu()
	{
		onMenu?(overflow)
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		hoverArea = DesktopHoverTracking.replace(
			in: self,
			previous: hoverArea,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
		)
		if let window
		{
			isHovered = visibleRect.contains(convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			))
		}
		else
		{
			isHovered = false
		}
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		queueView?.clearRowHovers(except: self)
	}

	func clearHover()
	{
		isHovered = false
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
	}

	override func resetCursorRects()
	{
		super.resetCursorRects()
		if canDrag
		{
			addCursorRect(
				NSRect(
					x: 0,
					y: 0,
					width: Self.leadingInset,
					height: bounds.height
				),
				cursor: .openHand
			)
		}
	}

	private static let gripArtwork: NSImage =
	{
		let image = NSImage(size: NSSize(
			width: 14,
			height: 14
		))
		image.lockFocus()
		for x: CGFloat in [0, 3]
		{
			DesktopIcons.draw(
				.dotsVertical,
				in: NSRect(
					x: x,
					y: 1,
					width: 12,
					height: 12
				),
				tint: .black
			)
		}
		image.unlockFocus()
		image.isTemplate = true
		return image
	}()

	private func updateGripVisibility()
	{
		NSAnimationContext.runAnimationGroup
		{
			context in
			context.duration = 0.15
			grip.animator().alphaValue = isHovered && canDrag ? 1 : 0
		}
	}

	override func mouseDown(with event: NSEvent)
	{
		trackDrag(with: event)
	}

	func trackDrag(with event: NSEvent)
	{
		guard canDrag, let window, let queueView
		else
		{
			return
		}
		isHovered = true
		var moved = false
		var released = false
		NSCursor.closedHand.push()
		defer
		{
			NSCursor.pop()
			if !released
			{
				queueView.cancelReordering()
			}
		}
		while queueView.window === window, canDrag
		{
			if moved, queueView.reorderSession?.row !== self
			{
				return
			}
			guard let next = window.nextEvent(
				matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
				until: Date(timeIntervalSinceNow: 0.1),
				inMode: .eventTracking,
				dequeue: true
			)
			else
			{
				if !window.isVisible || !NSApp.isActive
				{
					return
				}
				continue
			}
			if next.type == .keyDown
			{
				if next.keyCode == 53
				{
					return
				}
				window.sendEvent(next)
				continue
			}
			if next.type == .leftMouseUp
			{
				if moved
				{
					queueView.endReordering(at: next.locationInWindow)
				}
				released = true
				return
			}
			if !moved, hypot(
				next.locationInWindow.x - event.locationInWindow.x,
				next.locationInWindow.y - event.locationInWindow.y
			) > 3
			{
				moved = queueView.beginReordering(
					self,
					at: event.locationInWindow
				)
			}
			if moved
			{
				queueView.updateReordering(
					at: next.locationInWindow,
					event: next
				)
			}
		}
	}

}

@MainActor
private final class QueueDragHandle: NSImageView
{
	weak var owner: ComposerQueueRow?
	override func resetCursorRects()
	{
		super.resetCursorRects()
		addCursorRect(
			bounds,
			cursor: .openHand
		)
	}
	override func mouseDown(with event: NSEvent)
	{
		owner?.trackDrag(with: event)
	}

}
