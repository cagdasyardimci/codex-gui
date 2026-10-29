import AppKit

/// Complete composer submission control; the feature owns eligibility and command routing.
@MainActor
final class ComposerSubmissionButton: DesktopLayerButton
{
	enum Role
	{
		case send
		case resume
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
		case .resume: title = "Resume"
		case .stop: title = "Stop"
		}
		super.init(frame: .zero)
		self.title = title
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Controls.prominentButton)
		image = role == .resume ? DesktopIcons.image(
			.playSm,
			size: 16
		) : DesktopIcons.image(
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
			keyEquivalentModifierMask = [.command]
		}
		switch role
		{
		case .send:
			setAccessibilityLabel("Send message")
			setAccessibilityIdentifier("conversation-send")
			toolTip = nil
		case .resume:
			setAccessibilityLabel("Resume")
			setAccessibilityIdentifier("conversation-resume")
			toolTip = nil
		case .stop:
			setAccessibilityLabel("Stop current task")
			setAccessibilityIdentifier("conversation-stop")
			toolTip = nil
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
