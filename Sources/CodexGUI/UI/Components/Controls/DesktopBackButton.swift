import AppKit

@MainActor
final class DesktopBackButton: DesktopStyledButton
{
	init(
		target: AnyObject? = nil,
		action: Selector? = nil,
		symbol: DesktopIcon = .chevronLeft
	)
	{
		super.init(
			title: "Back",
			presentation: .sidebarIcon,
			size: .small
		)
		self.target = target
		self.action = action
		self.symbol = symbol
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
