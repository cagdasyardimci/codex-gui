import AppKit

@MainActor
final class SettingsSidebarButton: DesktopHoverButton
{
	private let icon: DesktopIcon
	var isSelected = false
	{
		didSet
		{
			needsDisplay = true
		}
	}

	init(
		title: String,
		icon: DesktopIcon
	)
	{
		self.icon = icon
		super.init(frame: .zero)
		self.title = title
		isBordered = false
		setButtonType(.momentaryChange)
		setAccessibilityLabel(title)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isSelected || isHovered || isHighlighted
		{
			AppKitColorTokens.settingsSidebarSelection.setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: ShapeTokens.SidebarSelection.cornerRadius,
				curve: ShapeTokens.SidebarSelection.cornerCurve
			).fill()
		}
		DesktopIcons.draw(
			icon,
			in: NSRect(
				x: 8,
				y: (bounds.height - 16) / 2,
				width: 16,
				height: 16
			),
			tint: AppKitColorTokens.settingsPrimaryText
		)
		let text = NSAttributedString(
			string: title,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Settings.sidebarRow),
				.foregroundColor: AppKitColorTokens.settingsPrimaryText,
			]
		)
		text.draw(in: NSRect(
			x: 32,
			y: (bounds.height - text.size().height) / 2,
			width: max(
				0,
				bounds.width - 40
			),
			height: text.size().height
		))
	}
}

@MainActor
final class SettingsSurfaceView: DesktopSurface
{
	var showsTrailingSeparator = false

	init(color: NSColor)
	{
		super.init(color)
		clipsToBounds = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		if showsTrailingSeparator
		{
			AppKitColorTokens.settingsSidebarSelection.setFill()
			NSRect(
				x: bounds.maxX - 0.5,
				y: bounds.minY,
				width: 0.5,
				height: bounds.height
			).fill()
		}
	}
}
