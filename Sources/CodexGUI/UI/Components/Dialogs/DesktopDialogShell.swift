import AppKit

/// Complete desktop dialog chrome with a content slot for richer confirmations and forms.
@MainActor
final class DesktopDialogShell: DesktopSurface
{
	enum Style
	{
		case standard, projectEdit, site, textEntry
	}

	enum ActionLayout
	{
		case horizontal, vertical
	}

	static let preferredWidth: CGFloat = 420
	let titleLabel: NSTextField
	let messageLabel: NSTextField?
	let closeButton = DesktopStyledButton(
		title: "Close",
		presentation: .sidebarIcon,
		size: .small
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
		titleIcon: DesktopIcon? = nil,
		style: Style = .standard,
		actionLayout: ActionLayout = .horizontal
	)
	{
		titleLabel = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Dialog.title
		)
		messageLabel = message.map(DesktopDialogMessageLabel.init)
		var actionViews: [NSView] = leadingAction.map
		{
			[$0, NSView()]
		} ?? [NSView()]
		actionViews += actions
		if actionLayout == .vertical
		{
			actionsRow = AppKitLayout.verticalStack(
				actions,
				spacing: 8
			)
		}
		else
		{
			actionsRow = AppKitLayout.horizontalStack(
				actionViews,
				spacing: 12
			)
		}
		super.init(
			style == .projectEdit || style == .site ? AppKitColorTokens
				.searchPanel : AppKitColorTokens.sidebar,
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
		titleLabel.textColor = AppKitColorTokens.primaryText
		titleLabel.setContentCompressionResistancePriority(
			.required,
			for: .vertical
		)
		if style == .projectEdit
		{
			closeButton.presentation = .icon
		}
		closeButton.symbol = .xCrossed
		closeButton.target = self
		closeButton.action = #selector(closeDialog)
		closeButton.keyEquivalent = "\u{1b}"
		closeButton.setAccessibilityLabel("Close \(title)")
		NSLayoutConstraint.activate([
			closeButton.widthAnchor.constraint(equalToConstant: 24),
			closeButton.heightAnchor.constraint(equalToConstant: 24),
		])
		var headingViews: [NSView] = []
		if let titleIcon
		{
			let icon = NSImageView(image: DesktopIcons.image(titleIcon))
			icon.contentTintColor = AppKitColorTokens.primaryText
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
		if actionLayout == .vertical
		{
			if let leadingAction
			{
				rows.append(AppKitLayout.horizontalStack(
					[leadingAction, NSView()],
					spacing: 0
				))
			}
			for action in actions
			{
				action.widthAnchor.constraint(equalTo: actionsRow.widthAnchor).isActive = true
			}
		}
		rows.append(actionsRow)
		let stack = AppKitLayout.verticalStack(
			rows,
			spacing: style == .textEntry ? 12 : 14
		)
		stack.setCustomSpacing(
			style == .textEntry ? 4 : 8,
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
		self.setTypographyRole(TypographyTokens.Dialog.message)
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
		let paragraph = (AppKitFontResolver.textAttributes(
			TypographyTokens.Dialog.message,
			font: font
		)[.paragraphStyle] as? NSParagraphStyle)?
			.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			attributedStringValue = NSAttributedString(
				string: stringValue,
				attributes: [
					.font: AppKitFontResolver.font(TypographyTokens.Dialog.message),
					.foregroundColor: AppKitColorTokens.secondaryText,
					.paragraphStyle: paragraph,
				]
			)
		}
	}
}
