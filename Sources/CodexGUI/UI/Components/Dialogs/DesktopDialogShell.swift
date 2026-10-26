import AppKit

/// Complete desktop dialog chrome with a content slot for richer confirmations and forms.
@MainActor
final class DesktopDialogShell: DesktopSurface
{
	static let preferredWidth: CGFloat = 420
	let titleLabel: NSTextField
	let messageLabel: NSTextField?
	let closeButton = DesktopStyledButton(
		title: "Close",
		presentation: .nativeIcon
	)
	let actionsRow: NSStackView
	var onClose: (() -> Void)?
	private var widthConstraint: NSLayoutConstraint!

	init(
		title: String,
		message: String? = nil,
		content: NSView? = nil,
		actions: [NSButton],
		leadingAction: NSButton? = nil,
		titleIcon: DesktopIcon? = nil
	)
	{
		titleLabel = NSTextField(wrappingLabelWithString: title)
		messageLabel = message.map(DesktopDialogMessageLabel.init)
		var actionViews: [NSView] = leadingAction.map
		{
			[$0, NSView()]
		} ?? [NSView()]
		actionViews += actions
		actionsRow = AppKitLayout.horizontalStack(
			actionViews,
			spacing: 12
		)
		super.init(
			AppKitColorTokens.sidebar,
			cornerRadius: 20,
			bordered: true,
			borderWidth: 0.5
		)
		setAccessibilityLabel(title)
		for button in actions + (leadingAction.map
		{
			[$0]
		} ?? []) + [closeButton]
		{
			(button as? DesktopStyledButton)?.keyboardFocusPolicy = .dialog
		}
		titleLabel.font = .systemFont(
			ofSize: 20,
			weight: .semibold
		)
		titleLabel.textColor = .labelColor
		titleLabel.setContentCompressionResistancePriority(
			.required,
			for: .vertical
		)
		AppKitControlStyling.styleButton(
			closeButton,
			icon: .xCrossed
		)
		closeButton.imagePosition = .imageOnly
		closeButton.contentTintColor = AppKitColorTokens.secondaryText
		closeButton.target = self
		closeButton.action = #selector(closeDialog)
		closeButton.keyEquivalent = "\u{1b}"
		closeButton.setAccessibilityLabel("Close \(title)")
		NSLayoutConstraint.activate([
			closeButton.widthAnchor.constraint(equalToConstant: 16),
			closeButton.heightAnchor.constraint(equalToConstant: 16),
		])
		var headingViews: [NSView] = []
		if let titleIcon
		{
			let icon = NSImageView(image: DesktopIcons.image(titleIcon))
			icon.contentTintColor = .labelColor
			icon.setAccessibilityElement(false)
			NSLayoutConstraint.activate([
				icon.widthAnchor.constraint(equalToConstant: 22),
				icon.heightAnchor.constraint(equalToConstant: 22),
			])
			headingViews.append(icon)
		}
		headingViews += [titleLabel, NSView(), closeButton]
		let heading = AppKitLayout.horizontalStack(
			headingViews,
			spacing: 12
		)
		heading.alignment = .centerY
		NSLayoutConstraint.activate([
			closeButton.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
			closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
		])
		closeButton.setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		titleLabel.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		heading.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
		var rows: [NSView] = [heading]
		if let messageLabel
		{
			rows.append(messageLabel)
		}
		if let content
		{
			rows.append(content)
		}
		rows.append(actionsRow)
		let stack = AppKitLayout.verticalStack(
			rows,
			spacing: 14
		)
		stack.setCustomSpacing(
			8,
			after: heading
		)
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 20
		)
		for row in rows
		{
			row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		widthConstraint = widthAnchor.constraint(equalToConstant: Self.preferredWidth)
		widthConstraint.isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func resize(window: NSWindow)
	{
		let available = window.sheetParent?.contentView?.bounds.width ?? Self.preferredWidth
		widthConstraint.constant = min(
			Self.preferredWidth,
			max(
				1,
				available
			)
		)
		layoutSubtreeIfNeeded()
		window.setContentSize(fittingSize)
	}

	@objc private func closeDialog()
	{
		onClose?()
	}
}

/// Gives wrapping dialog prose one line-height and appearance-aware foreground owner.
@MainActor
private final class DesktopDialogMessageLabel: NSTextField
{
	init(_ message: String)
	{
		super.init(frame: .zero)
		isEditable = false
		isSelectable = false
		isBordered = false
		drawsBackground = false
		usesSingleLineMode = false
		cell?.wraps = true
		cell?.isScrollable = false
		stringValue = message
		font = .systemFont(ofSize: 14)
		textColor = AppKitColorTokens.secondaryText
		setContentCompressionResistancePriority(
			.required,
			for: .vertical
		)
		refreshText()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshText()
	}

	private func refreshText()
	{
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 21
		paragraph.maximumLineHeight = 21
		paragraph.lineBreakMode = .byWordWrapping
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			attributedStringValue = NSAttributedString(
				string: stringValue,
				attributes: [
					.font: NSFont.systemFont(ofSize: 14),
					.foregroundColor: AppKitColorTokens.secondaryText,
					.paragraphStyle: paragraph,
				]
			)
		}
	}
}
