import AppKit

@MainActor
final class SidebarMenuRow: NSButton
{
	var onHover: (() -> Void)?
	var onInvoke: (() -> Void)?
	var menuHighlighted = false
	{
		didSet
		{
			needsDisplay = true
		}
	}
	let leadingIcon: NSImage?
	let opensSubmenu: Bool
	private var tracking: NSTrackingArea?
	private typealias Layout = LayoutTokens.SidebarMenu

	init(
		title: String,
		icon: NSImage? = nil,
		opensSubmenu: Bool = false,
		selected: Bool = false
	)
	{
		leadingIcon = icon
		self.opensSubmenu = opensSubmenu
		super.init(frame: .zero)
		self.title = title
		state = selected ? .on : .off
		isBordered = false
		focusRingType = .none
		target = self
		action = #selector(invoke)
		setAccessibilityRole(.menuItem)
		setAccessibilityLabel(title)
		setAccessibilityValue(opensSubmenu ? nil : selected ? "Selected" : "Not selected")
	}

	required init?(coder: NSCoder)
	{
		nil
	}
	override var isFlipped: Bool
	{
		true
	}
	override var acceptsFirstResponder: Bool
	{
		true
	}
	@objc private func invoke()
	{
		onInvoke?()
	}
	override func accessibilityPerformPress() -> Bool
	{
		onInvoke?()
		return true
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let tracking
		{
			removeTrackingArea(tracking)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		tracking = area
	}

	override func mouseEntered(with event: NSEvent)
	{
		onHover?()
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if menuHighlighted
		{
			AppKitColorTokens.rowHighlight.setFill()
			NSBezierPath(
				roundedRect: bounds,
				xRadius: ShapeTokens.SidebarMenu.rowRadius,
				yRadius: ShapeTokens.SidebarMenu.rowRadius
			).fill()
		}
		var textX = Layout.horizontalInset
		if let leadingIcon
		{
			DesktopIcons.draw(
				leadingIcon,
				in: NSRect(
					x: textX,
					y: bounds.midY - Layout.iconSize / 2,
					width: Layout.iconSize,
					height: Layout.iconSize
				),
				tint: AppKitColorTokens.primaryText
			)
			textX += Layout.iconSize + Layout.iconSpacing
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		DesktopTextRendering.withFontSmoothingDisabled
		{
			(title as NSString).draw(
				in: NSRect(
					x: textX,
					y: Layout.verticalInset,
					width: bounds.width - textX - Layout
						.horizontalInset - Layout.iconSize - Layout
						.iconSpacing,
					height: TypographyTokens.SidebarMenu.lineHeight
				),
				withAttributes: [
					.font: AppKitFontResolver
						.font(TypographyTokens.SidebarMenu.row),
					.foregroundColor: AppKitColorTokens.primaryText,
					.paragraphStyle: paragraph,
				]
			)
		}
		if opensSubmenu || state == .on
		{
			DesktopIcons.draw(
				DesktopIcons.image(opensSubmenu ? .chevronRight : .check),
				in: NSRect(
					x: bounds.maxX - Layout.horizontalInset - Layout.iconSize,
					y: bounds.midY - Layout.iconSize / 2,
					width: Layout.iconSize,
					height: Layout.iconSize
				),
				tint: opensSubmenu ? AppKitColorTokens
					.secondaryText : AppKitColorTokens.primaryText
					.withAlphaComponent(menuHighlighted ? 1 : 0.75)
			)
		}
	}
}
