import AppKit

/// Complete native inline icon action with semantic sizes and platform focus/activation.
@MainActor
final class DesktopNativeIconButton: DesktopStyledButton
{
	enum IconSize
	{
		case small, standard
	}

	private let side: CGFloat

	init(
		title: String = "",
		label: String,
		icon: DesktopIcon? = nil,
		size: IconSize = .standard,
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		side = size == .small ? 22 : 24
		super.init(
			title: title,
			presentation: .nativeIcon
		)
		self.target = target
		self.action = action
		symbol = icon
		setLabel(
			label,
			toolTip: title.isEmpty ? nil : title
		)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: side),
			heightAnchor.constraint(equalToConstant: side),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: side,
			height: side
		)
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
