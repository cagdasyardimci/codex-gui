import AppKit

/// Complete image-viewer close control with shared overlay appearance and native activation.
@MainActor
final class ExpandedImageCloseButton: DesktopStyledButton
{
	var usesLightSurface = false
	{
		didSet
		{
			presentation = .imageOverlay(light: usesLightSurface)
		}
	}

	init()
	{
		super.init(
			title: "Close",
			presentation: .imageOverlay(light: false),
			size: .regular
		)
		image = DesktopIcons.image(
			.xCrossed,
			size: LayoutTokens.Button.artworkSize
		)
		imagePosition = .imageOnly
		focusRingType = .none
		toolTip = "Close viewer"
		setAccessibilityLabel("Close image")
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
