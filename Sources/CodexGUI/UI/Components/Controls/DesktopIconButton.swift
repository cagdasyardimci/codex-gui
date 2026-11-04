import AppKit

/// App-styled icon action with semantic sizes and platform activation.
@MainActor
final class DesktopIconButton: DesktopStyledButton
{
	enum IconSize
	{
		case small, standard
	}

	init(
		title: String = "",
		label: String,
		icon: DesktopIcon? = nil,
		size: IconSize = .standard,
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		super.init(
			title: title,
			presentation: .sidebarIcon,
			size: size == .small ? .mini : .small
		)
		self.target = target
		self.action = action
		symbol = icon
		setLabel(
			label,
			toolTip: title.isEmpty ? nil : title
		)

	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setLabel(
		_ label: String,
		toolTip: String? = nil
	)
	{
		setAccessibilityLabel(label)
		self.toolTip = toolTip ?? label
	}
}
