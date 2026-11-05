import AppKit

/// Keeps the numeric editor and its unit in one settings accessory.
@MainActor
final class SettingsNumberInput: NSView
{
	init(
		field: NSTextField,
		unit: String
	)
	{
		super.init(frame: .zero)
		field.alignment = .left
		let label = DesktopLineBoxLabel(
			unit,
			role: TypographyTokens.Connections.body
		)
		label.textColor = AppKitColorTokens.settingsSecondaryText
		AppKitLayout.pin(
			AppKitLayout.horizontalStack(
				[field, label],
				spacing: 8
			),
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
