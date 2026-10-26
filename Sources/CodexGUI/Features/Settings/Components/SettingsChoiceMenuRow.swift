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
		showsCheckbox: Bool
	)
	{
		super.init(
			content: Content(
				title: title,
				icon: icon,
				subtitle: detail,
				indicator: showsCheckbox ? .checkbox : .checkmark,
				checked: checked
			)
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
