import AppKit

/// Complete native inline popup presentation; callers own menu data and selection routing.
@MainActor
final class DesktopPopupButton: NSPopUpButton
{
	enum Size
	{
		case compact, small
	}

	var size: Size = .compact
	{
		didSet
		{
			font = size == .small ? .systemFont(ofSize: 11)
				: AppKitFontResolver.font(TypographyTokens.Controls.button)
		}
	}

	convenience init()
	{
		self.init(
			frame: .zero,
			pullsDown: false
		)
	}

	override init(
		frame buttonFrame: NSRect,
		pullsDown flag: Bool
	)
	{
		super.init(
			frame: buttonFrame,
			pullsDown: flag
		)
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Controls.button)
		contentTintColor = .secondaryLabelColor
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
