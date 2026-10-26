import AppKit

/// A full-width card row owns padding around descriptive or richer custom content.
@MainActor
class SettingsContentRow: NSView
{
	init(content: NSView)
	{
		super.init(frame: .zero)
		content.translatesAutoresizingMaskIntoConstraints = false
		addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 16
			),
			content.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -16
			),
			content.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 12
			),
			content.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -12
			),
		])
	}

	convenience init(
		title: String,
		detail: String
	)
	{
		let label = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.rowLabel
		)
		let description = DesktopLineBoxLabel(
			detail,
			role: TypographyTokens.Connections.caption
		)
		description.textColor = AppKitColorTokens.settingsSecondaryText
		let text = AppKitLayout.verticalStack(
			[label, description],
			spacing: 2
		)
		for view in text.arrangedSubviews
		{
			view.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
		}
		self.init(content: text)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
