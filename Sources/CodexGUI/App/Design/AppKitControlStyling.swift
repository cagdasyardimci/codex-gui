import AppKit

/// Shared native control presentation defaults.
@MainActor
enum AppKitControlStyling
{
	static func styleButton(
		_ button: NSButton,
		icon: DesktopIcon? = nil,
		prominent: Bool = false
	)
	{
		button.bezelStyle = .inline
		button.isBordered = false
		button.controlSize = .small
		button.font = AppKitFontResolver.font(prominent
			? TypographyTokens.Controls.prominentButton : TypographyTokens.Controls.button)
		button.contentTintColor = prominent ? .labelColor : .secondaryLabelColor
		if let icon
		{
			button.image = DesktopIcons.image(
				icon,
				size: LayoutTokens.LayoutDefaults.buttonIconSize
			)
			button.imagePosition = .imageLeading
		}
		button.toolTip = button.toolTip ?? button.title
		button.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	static func sectionLabel(_ text: String) -> NSTextField
	{
		let label = NSTextField(labelWithString: text)
		label.font = AppKitFontResolver.font(TypographyTokens.Controls.section)
		label.textColor = .secondaryLabelColor
		return label
	}

}
