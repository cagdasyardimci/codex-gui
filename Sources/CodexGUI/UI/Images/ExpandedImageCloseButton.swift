import AppKit

/// Complete image-viewer close control with shared overlay appearance and native activation.
@MainActor
final class ExpandedImageCloseButton: DesktopStyledButton
{
	var usesDiagramLayout = false
	{
		didSet
		{
			presentation = .imageOverlay(
				diagram: usesDiagramLayout,
				close: true
			)
		}
	}

	init()
	{
		super.init(
			title: "Close",
			presentation: .imageOverlay(
				diagram: false,
				close: true
			),
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
