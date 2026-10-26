import AppKit

/// Bridges closure actions to AppKit while retaining the shared button's presentation.
@MainActor
class DesktopActionButton: DesktopStyledButton
{
	var onAction: (() -> Void)?

	override init(
		title: String,
		presentation: Presentation = .tab(selected: true),
		size: Size = .compact
	)
	{
		super.init(
			title: title,
			presentation: presentation,
			size: size
		)
		target = self
		action = #selector(invokeAction)
	}

	convenience init(
		title: String,
		presentation: Presentation,
		size: Size = .compact,
		action: @escaping () -> Void
	)
	{
		self.init(
			title: title,
			presentation: presentation,
			size: size
		)
		onAction = action
	}

	convenience init(
		icon: DesktopIcon,
		label: String,
		presentation: Presentation = .icon,
		size: Size = .compact,
		action: @escaping () -> Void
	)
	{
		self.init(
			title: "",
			presentation: presentation,
			size: size,
			action: action
		)
		image = DesktopIcons.image(icon)
		setAccessibilityLabel(label)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	@objc func invokeAction()
	{
		onAction?()
	}
}
