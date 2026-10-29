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
	private var hoverArea: NSTrackingArea?

	private var isHovered = false

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
		let handle = NSImageView(image: DesktopIcons.image(
			.followup,
			size: 14
		))
		handle.contentTintColor = AppKitColorTokens.composerQueueLeadingGlyph
		handle.setAccessibilityElement(false)
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

}
