import AppKit

/// A compact account-style row owns both labels and its read-only value presentation.
@MainActor
final class SettingsReadOnlyValueRow: NSView
{
	private let valueLabel: DesktopLineBoxLabel

	init(
		title: String,
		value: String
	)
	{
		valueLabel = DesktopLineBoxLabel(
			value,
			role: TypographyTokens.Connections.body
		)
		super.init(frame: .zero)
		let label = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.rowLabel
		)
		valueLabel.textColor = AppKitColorTokens.settingsSecondaryText
		valueLabel.alignment = .right
		valueLabel.setAccessibilityLabel(title)
		let contents = AppKitLayout.horizontalStack(
			[label, NSView(), valueLabel],
			spacing: 20
		)
		contents.translatesAutoresizingMaskIntoConstraints = false
		addSubview(contents)
		NSLayoutConstraint.activate([
			contents.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 16
			),
			contents.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -16
			),
			contents.centerYAnchor.constraint(equalTo: centerYAnchor),
			heightAnchor.constraint(equalToConstant: 50),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setValue(
		_ value: String,
		help: String? = nil
	)
	{
		valueLabel.stringValue = value
		valueLabel.toolTip = help
	}
}
