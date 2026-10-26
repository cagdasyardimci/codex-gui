import AppKit

/// A section with an inline heading and optional explanatory text above its content.
@MainActor
final class SettingsDescriptiveSection: NSStackView
{
	init(
		title: String,
		detail: String,
		content: NSView
	)
	{
		super.init(frame: .zero)
		orientation = .vertical
		alignment = .leading
		spacing = 12
		let heading = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.section
		)
		addArrangedSubview(heading)
		if !detail.isEmpty
		{
			let description = DesktopLineBoxLabel(
				detail,
				role: TypographyTokens.Connections.caption
			)
			description.textColor = AppKitColorTokens.settingsSecondaryText
			addArrangedSubview(description)
			setCustomSpacing(
				4,
				after: heading
			)
		}
		addArrangedSubview(content)
		for view in arrangedSubviews
		{
			view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
