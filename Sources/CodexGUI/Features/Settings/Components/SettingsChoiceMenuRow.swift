import AppKit

/// Maps choice data to the shared menu item UI; selection remains owned by the menu.
@MainActor
final class SettingsChoiceMenuRow: DesktopMenuRow
{
	var onChoose: (() -> Void)?
	{
		get
		{
			onInvoke
		}
		set
		{
			onInvoke = newValue
		}
	}

	init(
		title: String,
		icon: NSImage?,
		checked: Bool,
		detail: String?,
		showsCheckbox: Bool,
		titleRole: TypographyTokens.Role = TypographyTokens.MenuRow.title,
		detailRole: TypographyTokens.Role = TypographyTokens.MenuRow.subtitle
	)
	{
		super.init(
			content: Content(
				title: title,
				icon: icon,
				subtitle: detail,
				indicator: showsCheckbox ? .checkbox : .checkmark,
				checked: checked
			),
			titleRole: titleRole,
			subtitleRole: detailRole
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
