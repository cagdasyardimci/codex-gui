import AppKit

@MainActor
final class DesktopBackButton: DesktopStyledButton
{
	init(
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		super.init(
			title: "Back",
			presentation: .nativeIcon
		)
		self.target = target
		self.action = action
		symbol = .chevronLeft
		widthAnchor.constraint(equalToConstant: 24).isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
