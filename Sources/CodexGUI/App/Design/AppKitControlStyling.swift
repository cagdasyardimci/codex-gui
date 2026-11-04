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
		button.setTypographyRole(prominent
			? TypographyTokens.Controls.prominentButton : TypographyTokens.Controls.button)
		button.contentTintColor = prominent ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
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
		label.setTypographyRole(TypographyTokens.Controls.section)
		label.textColor = AppKitColorTokens.secondaryText
		return label
	}

}
