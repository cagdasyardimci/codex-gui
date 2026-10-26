import AppKit

/// Maps sidebar menu choices to the shared menu item UI.
@MainActor
final class SidebarMenuRow: DesktopMenuRow
{
	init(
		title: String,
		icon: NSImage? = nil,
		opensSubmenu: Bool = false,
		selected: Bool = false
	)
	{
		super.init(
			content: Content(
				title: title,
				icon: icon,
				indicator: opensSubmenu ? .submenu : .checkmark,
				checked: selected
			)
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
