import AppKit

/// Keeps native button actions with the composer's measured icon and title insets.
@MainActor
final class ComposerPermissionButton: DesktopHoverButton
{
	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		cell = ComposerPermissionButtonCell(textCell: "")
		imageScaling = .scaleProportionallyUpOrDown
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}

	override var intrinsicContentSize: NSSize
	{
		let size = super.intrinsicContentSize
		let titleWidth = (title as NSString).size(withAttributes: [
			.font: font ?? AppKitFontResolver.font(TypographyTokens.Composer.preference),
		]).width
		return NSSize(
			width: (cell as? ComposerPermissionButtonCell)?.requestedWidth(titleWidth: titleWidth)
				?? PermissionControlLayout().requestedWidth(titleWidth: titleWidth),
			height: size.height
		)
	}
}
