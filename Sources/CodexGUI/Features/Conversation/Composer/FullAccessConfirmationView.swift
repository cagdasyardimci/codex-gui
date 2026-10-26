import AppKit

@MainActor
final class FullAccessConfirmationView: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	let cancelButton = DesktopStyledButton(
		title: "Cancel",
		presentation: .secondary,
		size: .regular
	)
	let confirmButton = DesktopStyledButton(
		title: "Confirm",
		presentation: .destructive,
		size: .regular
	)
	let riskText = FullAccessRiskTextView()

	override func loadView()
	{
		configureRiskText()
		let introduction = makeIntroduction()
		let capabilities = makeCapabilitiesSection()
		let content = AppKitLayout.verticalStack(
			[introduction, capabilities, riskText],
			spacing: 14
		)
		for row in [introduction, capabilities, riskText]
		{
			row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
		}
		configureButton(
			cancelButton,
			confirm: false
		)
		configureButton(
			confirmButton,
			confirm: true
		)
		let dialog = DesktopDialogShell(
			title: "Turn on Full Access?",
			content: content,
			actions: [cancelButton, confirmButton],
			titleIcon: .triangleExclamationErrorWarning
		)
		dialog.onClose =
		{
			[weak self] in self?.onDecision?(false)
		}
		cancelButton.nextKeyView = confirmButton
		confirmButton.nextKeyView = dialog.closeButton
		dialog.closeButton.nextKeyView = cancelButton
		view = dialog
	}

	private func makeIntroduction() -> NSTextField
	{
		wrappingLabel(
			"Codex will be able to run commands, use the internet, and create and edit "
				+ "files anywhere on this computer without your permission. This includes "
				+ "but is not limited to:",
			size: 14
		)
	}

	private func makeCapabilitiesSection() -> NSView
	{
		let capabilities = DesktopSurface(
			AppKitColorTokens.input,
			cornerRadius: 16
		)
		let rows = AppKitLayout.verticalStack(
			[
				capability(
					"Files and folders",
					description: "Read, create, modify, upload, or delete files "
						+ "anywhere on this computer",
					icon: .folderOpen,
					tint: .systemBlue
				),
				separator(),
				capability(
					"Terminal commands",
					description: "Run commands, install software, and change system settings",
					icon: .terminal,
					tint: ApprovalPopoverStyle.icon
				),
				separator(),
				capability(
					"Internet and connected apps",
					description: "Access websites, send data, and use enabled plugins",
					icon: .globeRealTimeSearch,
					tint: .systemCyan
				),
			],
			spacing: 10
		)
		AppKitLayout.pin(
			rows,
			to: capabilities,
			inset: 16
		)
		for row in rows.arrangedSubviews
		{
			row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
		}

		return capabilities
	}

	private func configureRiskText()
	{
		riskText.isEditable = false
		riskText.isSelectable = true
		riskText.drawsBackground = false
		riskText.textContainerInset = .zero
		riskText.textContainer?.lineFragmentPadding = 0
		riskText.textContainer?.widthTracksTextView = true
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = 3
		let text = NSMutableAttributedString(
			string: "This comes with risks like loss or exposure of sensitive data and prompt "
				+ "injection. You can turn this off. ",
			attributes: [
				.font: NSFont.systemFont(ofSize: 14),
				.foregroundColor: ApprovalPopoverStyle.secondary,
				.paragraphStyle: paragraph,
			]
		)
		text.append(NSAttributedString(
			string: "Learn more",
			attributes: [
				.font: NSFont.systemFont(ofSize: 14),
				.link: DocumentationLinks.sandboxing,
			]
		))
		riskText.linkTextAttributes = [.foregroundColor: NSColor.linkColor]
		riskText.textStorage?.setAttributedString(text)
	}

	private func configureButton(
		_ button: DesktopStyledButton,
		confirm: Bool
	)
	{
		button.target = self
		button.action = confirm ? #selector(confirmAccess) : #selector(cancel)
		button.hasDestructiveAction = confirm
		button.keyEquivalent = confirm ? "\r" : "\u{1b}"
	}

	private func capability(
		_ title: String,
		description: String,
		icon name: DesktopIcon,
		tint: NSColor
	) -> NSView
	{
		let heading = NSTextField(labelWithString: title)
		heading.font = .systemFont(
			ofSize: 13,
			weight: .semibold
		)
		let descriptionLabel = wrappingLabel(
			description,
			size: 12
		)
		let labels = AppKitLayout.verticalStack(
			[heading, descriptionLabel],
			spacing: 3
		)
		let icon = symbol(
			name,
			tint: tint
		)
		let row = AppKitLayout.horizontalStack(
			[icon, labels],
			spacing: 14
		)
		labels.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
		row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
		return row
	}

	private func wrappingLabel(
		_ text: String,
		size: CGFloat
	) -> NSTextField
	{
		let label = NSTextField(wrappingLabelWithString: text)
		label.font = .systemFont(ofSize: size)
		label.textColor = ApprovalPopoverStyle.secondary
		label.setContentCompressionResistancePriority(
			.required,
			for: .vertical
		)
		return label
	}

	private func symbol(
		_ name: DesktopIcon,
		tint: NSColor
	) -> NSImageView
	{
		let image = NSImageView()
		image.image = DesktopIcons.image(name)
		image.contentTintColor = tint
		image.widthAnchor.constraint(equalToConstant: 22).isActive = true
		image.heightAnchor.constraint(equalToConstant: 22).isActive = true
		return image
	}

	private func separator() -> NSView
	{
		let line = NSBox()
		line.boxType = .separator
		line.heightAnchor.constraint(equalToConstant: 1).isActive = true
		return line
	}

	@objc private func cancel()
	{
		onDecision?(false)
	}

	@objc private func confirmAccess()
	{
		onDecision?(true)
	}
}

/// The rich link paragraph grows with the shared dialog's available width.
@MainActor
final class FullAccessRiskTextView: NSTextView
{
	override var intrinsicContentSize: NSSize
	{
		guard let textContainer, let layoutManager
		else
		{
			return super.intrinsicContentSize
		}
		textContainer.containerSize = NSSize(
			width: bounds.width > 0 ? bounds.width : DesktopDialogShell.preferredWidth - 40,
			height: .greatestFiniteMagnitude
		)
		layoutManager.ensureLayout(for: textContainer)
		return NSSize(
			width: NSView.noIntrinsicMetric,
			height: ceil(layoutManager.usedRect(for: textContainer).height)
		)
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		let widthChanged = frame.width != newSize.width
		super.setFrameSize(newSize)
		if widthChanged
		{
			invalidateIntrinsicContentSize()
		}
	}
}
