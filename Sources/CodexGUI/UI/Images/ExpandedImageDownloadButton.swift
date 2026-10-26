import AppKit

/// Complete diagram actions own their overlay/step presentation and semantic dimensions.
@MainActor
final class ExpandedImageDownloadButton: DesktopStyledButton
{
	init(
		image: NSImage,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(
			title: "",
			presentation: .imageOverlay(light: true),
			size: .regular
		)
		self.image = image
		imagePosition = .imageOnly
		self.target = target
		self.action = action
		setAccessibilityLabel("Download image")
	}

	init(
		title: String,
		target: AnyObject?,
		action: Selector?
	)
	{
		super.init(
			title: title,
			presentation: .zoomStep,
			size: .regular
		)
		self.target = target
		self.action = action
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
