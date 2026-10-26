import AppKit

/// The sidebar compose action owns its cell, artwork, typography and row geometry.
@MainActor
final class SidebarNewChatButton: DesktopHoverButton
{
	init()
	{
		super.init(frame: .zero)
		title = "New chat"
		cell = NewChatButtonCell(textCell: title)
		AppKitControlStyling.styleButton(
			self,
			icon: .composeEditSquare
		)
		font = AppKitFontResolver.font(TypographyTokens.Sidebar.row)
		contentTintColor = AppKitColorTokens.sidebarText
		image = DesktopIcons.image(.composeEditSquare)
		alignment = .left
		setAccessibilityLabel("Start a new conversation")
		heightAnchor.constraint(equalToConstant: 30).isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
