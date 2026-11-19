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
		case startVoiceChat
		case endVoiceChat
	}

	let role: Role
	private var colorObservation: ThemeColorObservation?
	private var targetsExistingChat = false
	var reconnectsVoiceChat = false
	{
		didSet
		{
			if oldValue != reconnectsVoiceChat
			{
				setVoiceChatTarget(isExistingChat: targetsExistingChat)
			}
		}
	}

	init(role: Role)
	{
		self.role = role
		let title: String
		switch role
		{
		case .send: title = "Send"
		case .resume: title = "Resume"
		case .stop: title = "Stop"
		case .startVoiceChat, .endVoiceChat: title = ""
		}
		super.init(frame: .zero)
		self.title = title
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		self.setTypographyRole(TypographyTokens.Controls.prominentButton)
		switch role
		{
		case .send:
			image = DesktopIcons.image(
				.arrowUpLg,
				size: LayoutTokens.Composer.sendIconSize
			)
		case .resume:
			image = DesktopIcons.image(
				.playSm,
				size: 16
			)
		case .stop:
			image = DesktopIcons.image(
				.stopCircleFilled,
				size: LayoutTokens.composer.controlHeight
			)
		case .startVoiceChat:
			image = DesktopIcons.image(
				.voice5BarsSoundwave,
				size: LayoutTokens.Composer.sendIconSize
			)
		case .endVoiceChat:
			image = DesktopIcons.image(
				.x,
				size: LayoutTokens.Composer.sendIconSize
			)
		}
		imagePosition = .imageOnly
		colorObservation = ThemeColorObservation
		{
			[weak self] in
			self?.refreshEnabledPresentation()
		}
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
		}
		if role == .send || role == .resume
		{
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
		case .startVoiceChat:
			setAccessibilityIdentifier("conversation-start-voice-chat")
			setVoiceChatTarget(isExistingChat: false)
		case .endVoiceChat:
			setAccessibilityLabel("End voice chat")
			setAccessibilityIdentifier("conversation-end-voice-chat")
			toolTip = "End voice chat"
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

	func setVoiceChatTarget(isExistingChat: Bool)
	{
		targetsExistingChat = isExistingChat
		let label = reconnectsVoiceChat ? "Reconnect voice chat"
			: (isExistingChat ? "Start voice chat" : "Start new voice chat")
		guard role == .startVoiceChat, toolTip != label
		else
		{
			return
		}
		// Setting the native title changes the cell from image-only to overlapping text.
		image = DesktopIcons.image(
			reconnectsVoiceChat ? .regenerate : .voice5BarsSoundwave,
			size: LayoutTokens.Composer.sendIconSize
		)
		setAccessibilityLabel(label)
		toolTip = label
	}

	// The layer paints the full frame. Native inline insets would expand it beyond the square slot.
	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsetsZero
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
		contentTintColor = role == .stop ? AppKitColorTokens.primaryText : AppKitColorTokens
			.composerSendText
		guard role != .stop
		else
		{
			return
		}
		let enabledFill = role == .startVoiceChat || role == .endVoiceChat
			? AppKitColorTokens.composerVoice
			: AppKitColorTokens.composerSend
		layerBackgroundColor = isEnabled ? enabledFill : AppKitColorTokens.mutedText
	}
}
