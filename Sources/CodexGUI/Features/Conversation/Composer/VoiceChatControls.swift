import AppKit

/// The same session actions appear in the composer and in the window's floating controls.
@MainActor
final class VoiceChatControls: NSStackView
{
	let microphone: DesktopStyledButton
	let speakers: DesktopStyledButton
	let end: DesktopTooltipButton
	let orb: VoiceChatOrb?

	init(floating: Bool = false)
	{
		let presentation: DesktopStyledButton.Presentation = floating
			? .glyphOnlyIcon : .subduedGlyphOnlyIcon
		let controlSize = floating ? NSSize(
			width: LayoutTokens.Composer.floatingVoiceControlWidth,
			height: LayoutTokens.Composer.floatingVoiceControlHeight
		) : Self.composerControlSize
		microphone = Self.button(
			image: DesktopIcons.image(.mic),
			label: "Mute microphone",
			presentation: presentation,
			controlSize: controlSize
		)
		speakers = Self.button(
			image: floating ? DesktopIcons.image(.soundOnReadOutLoudSpeaker) : DesktopIcons
				.voiceSpeaker,
			label: "Mute speakers",
			presentation: presentation,
			controlSize: controlSize
		)
		let artwork = floating ? VoiceChatOrb(diameter: LayoutTokens.composer.controlHeight) : nil
		orb = artwork
		end = floating ? Self.button(
			image: nil,
			label: "End voice chat",
			presentation: presentation,
			controlSize: controlSize
		) : ComposerSubmissionButton(role: .endVoiceChat)

		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = floating ? 0 : LayoutTokens.composer.actionSpacing
		let controls: [NSView]
		if let artwork
		{
			end.setAccessibilityIdentifier("floating-end-voice-chat")
			end.addSubview(artwork)
			artwork.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				artwork.centerXAnchor.constraint(equalTo: end.centerXAnchor),
				artwork.centerYAnchor.constraint(equalTo: end.centerYAnchor),
			])
			controls = [microphone, ToolbarSeparatorView(), end, ToolbarSeparatorView(), speakers]
		}
		else
		{
			controls = [speakers, microphone, end]
		}
		for control in controls
		{
			addArrangedSubview(control)
		}
		if !floating
		{
			setCustomSpacing(
				LayoutTokens.Composer.voiceAudioControlSpacing,
				after: speakers
			)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		microphoneMuted: Bool,
		speakersMuted: Bool
	)
	{
		let floating = orb != nil
		let microphonePresentation: DesktopStyledButton.Presentation = floating ? .glyphOnlyIcon
			: microphoneMuted ? .mutedMicrophone : .subduedGlyphOnlyIcon
		if microphone.presentation != microphonePresentation
		{
			microphone.presentation = microphonePresentation
		}
		let speakerPresentation: DesktopStyledButton.Presentation = floating ? .glyphOnlyIcon
			: speakersMuted ? .mutedSpeaker : .subduedGlyphOnlyIcon
		if speakers.presentation != speakerPresentation
		{
			speakers.presentation = speakerPresentation
		}
		let microphoneImage = microphoneMuted && !floating ? DesktopIcons.mutedVoiceMicrophone
			: DesktopIcons.image(microphoneMuted ? .micOff : .mic)
		let speakerImage = floating
			? DesktopIcons.image(speakersMuted ? .soundOffSpeaker : .soundOnReadOutLoudSpeaker)
			: speakersMuted ? DesktopIcons.mutedVoiceSpeaker : DesktopIcons.voiceSpeaker
		Self.setAction(
			microphone,
			image: microphoneImage,
			label: microphoneMuted ? "Unmute microphone" : "Mute microphone"
		)
		Self.setAction(
			speakers,
			image: speakerImage,
			label: speakersMuted ? "Unmute speakers" : "Mute speakers"
		)
	}

	private static var composerControlSize: NSSize
	{
		let side = LayoutTokens.composer.controlHeight
		return NSSize(
			width: side,
			height: side
		)
	}

	private static func button(
		image: NSImage?,
		label: String,
		presentation: DesktopStyledButton.Presentation,
		controlSize: NSSize
	) -> DesktopStyledButton
	{
		let button = DesktopStyledButton(
			title: "",
			presentation: presentation,
			size: .small
		)
		setAction(
			button,
			image: image,
			label: label
		)
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: controlSize.width),
			button.heightAnchor.constraint(equalToConstant: controlSize.height),
		])
		return button
	}

	private static func setAction(
		_ button: DesktopStyledButton,
		image: NSImage?,
		label: String
	)
	{
		guard button.toolTip != label
		else
		{
			return
		}
		button.image = image
		button.imagePosition = .imageOnly
		button.setAccessibilityLabel(label)
		button.toolTip = label
	}
}
