import AppKit

/// The sidebar compose action owns its cell, artwork, typography and row geometry.
@MainActor
final class SidebarNewChatButton: DesktopHoverButton
{
	private var themeColorObservation: ThemeColorObservation?
	init(center: NotificationCenter = .default)
	{
		super.init(frame: .zero)
		title = "New chat"
		cell = NewChatButtonCell(textCell: title)
		alignment = .left
		AppKitControlStyling.styleButton(
			self,
			icon: .composeEditSquare
		)
		self.setTypographyRole(TypographyTokens.Sidebar.row)
		contentTintColor = AppKitColorTokens.sidebarText
		refreshThemeColors()
		themeColorObservation = ThemeColorObservation(center: center)
		{
			[weak self] in self?.refreshThemeColors()
		}
		image = DesktopIcons.image(.composeEditSquare)
		setAccessibilityLabel("Start a new conversation")
		heightAnchor.constraint(equalToConstant: 30).isActive = true
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshThemeColors()
	}

	private func refreshThemeColors()
	{
		contentTintColor = AppKitColorTokens.sidebarText
		let existing = attributedTitle
		guard existing.length > 0
		else
		{
			return
		}
		let styled = NSMutableAttributedString(attributedString: existing)
		let resolved = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.primaryText,
			for: self
		)
		let titleColor = NSColor(cgColor: resolved) ?? AppKitColorTokens.primaryText
		styled.addAttribute(
			.foregroundColor,
			value: titleColor,
			range: NSRange(
				location: 0,
				length: styled.length
			)
		)
		let position = imagePosition
		attributedTitle = styled
		imagePosition = position
		needsDisplay = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
