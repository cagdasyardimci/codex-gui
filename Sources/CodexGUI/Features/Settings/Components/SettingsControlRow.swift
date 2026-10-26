import AppKit

/// An ordinary control row owns its mutable text, label styles, padding and accessory column.
@MainActor
final class SettingsControlRow: NSView
{
	private let titleLabel: DesktopLineBoxLabel
	private let detailLabel: DesktopLineBoxLabel

	init(
		title: String,
		detail: String?,
		control: NSView
	)
	{
		titleLabel = DesktopLineBoxLabel(
			title,
			role: TypographyTokens.Connections.rowLabel
		)
		detailLabel = DesktopLineBoxLabel(
			detail ?? "",
			role: TypographyTokens.Connections.caption
		)
		super.init(frame: .zero)
		detailLabel.textColor = AppKitColorTokens.settingsSecondaryText
		detailLabel.isHidden = detail == nil
		SettingsRowLayout.install(
			labels: [titleLabel, detailLabel],
			control: control,
			in: self
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setTitle(_ title: String)
	{
		titleLabel.stringValue = title
	}

	func setDetail(_ detail: String?)
	{
		detailLabel.stringValue = detail ?? ""
		detailLabel.isHidden = detail == nil
	}

	func setDetailHelp(_ help: String?)
	{
		detailLabel.toolTip = help
	}
}
