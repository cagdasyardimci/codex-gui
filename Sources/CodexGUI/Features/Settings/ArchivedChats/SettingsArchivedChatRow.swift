import AppKit

/// An archived-chat row owns its title/date hierarchy and destructive/restore action presentation.
@MainActor
final class SettingsArchivedChatRow: NSView
{
	init(
		title: String,
		date: String,
		isEnabled: Bool,
		onUnarchive: @escaping () -> Void,
		onDelete: @escaping () -> Void
	)
	{
		super.init(frame: .zero)
		let unarchive = DesktopActionButton(title: "Unarchive")
		unarchive.isEnabled = isEnabled
		unarchive.onAction = onUnarchive
		let delete = DesktopActionButton(
			title: "Delete",
			presentation: .icon
		)
		delete.image = DesktopIcons.image(.trash)
		delete.setAccessibilityLabel("Delete \(title)")
		delete.isEnabled = isEnabled
		delete.onAction = onDelete
		let actions = NSStackView(views: [delete, unarchive])
		actions.spacing = 8
		let titleLabel = NSTextField(labelWithString: title)
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.Connections.rowLabel)
		titleLabel.textColor = AppKitColorTokens.settingsPrimaryText
		titleLabel.lineBreakMode = .byTruncatingTail
		titleLabel.toolTip = title
		let dateLabel = DesktopLineBoxLabel(
			date,
			role: TypographyTokens.Connections.caption
		)
		dateLabel.textColor = AppKitColorTokens.settingsSecondaryText
		SettingsRowLayout.install(
			labels: [titleLabel, dateLabel],
			control: actions,
			in: self
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
