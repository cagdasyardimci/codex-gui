import AppKit

/// Complete composer submission control; the feature owns eligibility and command routing.
@MainActor
final class ComposerSubmissionButton: DesktopLayerButton
{
	enum Role
	{
		case send
		case steer
		case stop
	}

	let role: Role

	init(role: Role)
	{
		self.role = role
		let title: String
		switch role
		{
		case .send: title = "Send"
		case .steer: title = "Steer"
		case .stop: title = "Stop"
		}
		super.init(frame: .zero)
		self.title = title
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Controls.prominentButton)
		image = DesktopIcons.image(
			role == .stop ? .stopCircleFilled : .arrowUpLg,
			size: role == .stop ? LayoutTokens.composer.controlHeight : LayoutTokens.Composer
				.sendIconSize
		)
		imagePosition = .imageOnly
		contentTintColor = role == .stop ? .labelColor : .white
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight),
			heightAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight),
		])
		if role != .stop
		{
			wantsLayer = true
			layer?.cornerRadius = ShapeTokens.Composer
				.controlRadius(forControlHeight: LayoutTokens.composer.controlHeight)
			keyEquivalent = "\r"
			keyEquivalentModifierMask = role == .send ? [.command] : [.command, .shift]
		}
		switch role
		{
		case .send:
			setAccessibilityLabel("Send message")
			setAccessibilityIdentifier("conversation-send")
			toolTip = "Send message (⌘Return)"
		case .steer:
			setAccessibilityLabel("Steer the active turn with this message")
			toolTip = "Steer the active turn (⇧⌘Return)"
		case .stop:
			setAccessibilityLabel("Stop current task")
			setAccessibilityIdentifier("conversation-stop")
			toolTip = "Stop"
		}
		refreshEnabledPresentation()
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var isEnabled: Bool
	{
		didSet
		{
			refreshEnabledPresentation()
		}
	}

	private func refreshEnabledPresentation()
	{
		guard role != .stop
		else
		{
			return
		}
		layerBackgroundColor = isEnabled ? AppKitColorTokens.composerSend : .tertiaryLabelColor
	}
}
