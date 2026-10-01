import AppKit

@MainActor
final class FullAccessConfirmationView: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	let cancelButton = FullAccessConfirmationButton(
		title: "Cancel",
		target: nil,
		action: nil
	)
	let confirmButton = FullAccessConfirmationButton(
		title: "Confirm",
		target: nil,
		action: nil
	)
	let riskText = NSTextView()

	override func loadView()
	{
		let surface = DesktopSurface(
			DesktopTheme.canvas,
			cornerRadius: 18,
			bordered: true
		)
		let warning = symbol(
			"exclamationmark.triangle",
			tint: .labelColor
		)
		let title = NSTextField(labelWithString: "Turn on Full Access?")
		title.font = .systemFont(
			ofSize: 20,
			weight: .semibold
		)
		let heading = AppKitLayout.horizontalStack(
			[warning, title],
			spacing: 10
		)
		let introduction = wrappingLabel(
			"Codex will be able to run commands, use the internet, and create and edit "
				+ "files anywhere on this computer without your permission. This includes "
				+ "but is not limited to:",
			size: 14
		)
		introduction.preferredMaxLayoutWidth = 478

		let capabilities = DesktopSurface(
			DesktopTheme.input,
			cornerRadius: 16
		)
		let rows = AppKitLayout.verticalStack(
			[
				capability(
					"Files and folders",
					description: "Read, create, modify, upload, or delete files "
						+ "anywhere on this computer",
					symbol: "folder.fill",
					tint: .systemBlue
				),
				separator(),
				capability(
					"Terminal commands",
					description: "Run commands, install software, and change system settings",
					symbol: "terminal.fill",
					tint: ApprovalPopoverStyle.icon
				),
				separator(),
				capability(
					"Internet and connected apps",
					description: "Access websites, send data, and use enabled plugins",
					symbol: "globe",
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

		configureRiskText()
		configureButton(
			cancelButton,
			confirm: false
		)
		configureButton(
			confirmButton,
			confirm: true
		)
		let actions = AppKitLayout.horizontalStack(
			[NSView(), cancelButton, confirmButton],
			spacing: 12
		)
		let stack = AppKitLayout.verticalStack(
			[heading, introduction, capabilities, riskText, actions],
			spacing: 14
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 20
		)
		for row in [introduction, capabilities, riskText, actions]
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		surface.widthAnchor.constraint(equalToConstant: 518).isActive = true
		surface.heightAnchor.constraint(greaterThanOrEqualToConstant: 422).isActive = true
		view = surface
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
		riskText.heightAnchor.constraint(equalToConstant: 44).isActive = true
	}

	private func configureButton(
		_ button: FullAccessConfirmationButton,
		confirm: Bool
	)
	{
		button.target = self
		button.action = confirm ? #selector(confirmAccess) : #selector(cancel)
		button.isBordered = false
		button.bezelStyle = .inline
		button.font = .systemFont(ofSize: 14)
		button.contentTintColor = confirm ? .systemRed : .labelColor
		button.confirmsFullAccess = confirm
		button.keyEquivalent = confirm ? "\r" : "\u{1b}"
		if confirm
		{
			button.image = NSImage(
				systemSymbolName: "exclamationmark.triangle",
				accessibilityDescription: nil
			)
			button.imagePosition = .imageLeading
		}
		button.widthAnchor.constraint(equalToConstant: confirm ? 114 : 86).isActive = true
		button.heightAnchor.constraint(equalToConstant: 36).isActive = true
	}

	private func capability(
		_ title: String,
		description: String,
		symbol name: String,
		tint: NSColor
	) -> NSView
	{
		let heading = NSTextField(labelWithString: title)
		heading.font = .systemFont(
			ofSize: 13,
			weight: .semibold
		)
		let labels = AppKitLayout.verticalStack(
			[heading, wrappingLabel(
				description,
				size: 12
			)],
			spacing: 3
		)
		let row = AppKitLayout.horizontalStack(
			[symbol(
				name,
				tint: tint
			), labels],
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
		_ name: String,
		tint: NSColor
	) -> NSImageView
	{
		let image = NSImageView()
		image.image = NSImage(
			systemSymbolName: name,
			accessibilityDescription: nil
		)
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
