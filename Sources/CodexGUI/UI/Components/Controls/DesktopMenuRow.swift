import AppKit

/// Complete menu item UI; callers provide content and actions rather than their own row layout.
@MainActor
class DesktopMenuRow: NSButton
{
	enum Indicator: Equatable
	{
		case none, checkmark, checkbox, submenu
	}

	enum Role: Equatable
	{
		case normal, destructive, warning
	}

	enum SuffixStyle: Equatable
	{
		case metadata, shortcut
	}

	struct Content
	{
		var title: String
		var icon: NSImage? = nil
		var subtitle: String? = nil
		var suffix = ""
		var suffixStyle = SuffixStyle.metadata
		var indicator = Indicator.none
		var checked = false
		var role = Role.normal
	}

	var content: Content
	{
		didSet
		{
			applyContent()
		}
	}
	var onHover: (() -> Void)?
	var onInvoke: (() -> Void)?
	var onKeyDown: ((NSEvent) -> Bool)?
	var menuHighlighted = false
	{
		didSet
		{
			refreshAppearance()
		}
	}
	var checked: Bool
	{
		get
		{
			state == .on
		}
		set
		{
			state = newValue ? .on : .off
			content.checked = newValue
		}
	}
	var suffix: String
	{
		get
		{
			content.suffix
		}
		set
		{
			content.suffix = newValue
		}
	}
	var leadingIcon: NSImage?
	{
		content.icon
	}
	var opensSubmenu: Bool
	{
		content.indicator == .submenu
	}
	var rowHeight: CGFloat
	{
		content.subtitle == nil ? LayoutTokens.MenuRow.height : LayoutTokens.MenuRow.detailedHeight
	}
	let titleLabel = NSTextField(labelWithString: "")
	let subtitleLabel = NSTextField(labelWithString: "")
	let iconView = NSImageView()
	let trailingImageView = NSImageView()
	let suffixLabel = NSTextField(labelWithString: "")
	private(set) var isHovered = false
	private var isKeyboardFocused = false
	private var tracking: NSTrackingArea?
	private var rowHeightConstraint: NSLayoutConstraint?
	private typealias Layout = LayoutTokens.MenuRow

	init(content: Content)
	{
		self.content = content
		super.init(frame: .zero)
		isBordered = false
		focusRingType = .none
		setButtonType(.momentaryChange)
		target = self
		action = #selector(invoke)
		setAccessibilityRole(.menuItem)
		for label in [titleLabel, subtitleLabel, suffixLabel]
		{
			label.lineBreakMode = .byTruncatingTail
			label.isSelectable = false
			label.setAccessibilityElement(false)
		}
		for icon in [iconView, trailingImageView]
		{
			icon.imageScaling = .scaleProportionallyDown
			icon.setAccessibilityElement(false)
		}
		for child in [iconView, titleLabel, subtitleLabel, suffixLabel, trailingImageView]
		{
			addSubview(child)
		}
		let height = heightAnchor.constraint(equalToConstant: rowHeight)
		height.isActive = true
		rowHeightConstraint = height
		applyContent()
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
		isEnabled
	}
	override var isEnabled: Bool
	{
		didSet
		{
			refreshAppearance()
		}
	}

	private func applyContent()
	{
		title = content.title
		state = content.checked ? .on : .off
		setAccessibilityLabel(content.title)
		setAccessibilityHelp(content.subtitle)
		if content.indicator == .checkmark || content.indicator == .checkbox
		{
			setAccessibilityValue(checked ? "Selected" : "Not selected")
		}
		else if content.suffixStyle == .metadata, !content.suffix.isEmpty
		{
			setAccessibilityValue(content.suffix)
		}
		else
		{
			setAccessibilityValue(nil)
		}
		titleLabel.stringValue = content.title
		subtitleLabel.stringValue = content.subtitle ?? ""
		subtitleLabel.isHidden = content.subtitle == nil
		suffixLabel.stringValue = content.suffix
		suffixLabel.isHidden = content.suffix.isEmpty
		iconView.image = content.icon
		iconView.isHidden = content.icon == nil || content.indicator == .checkbox
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.MenuRow.title)
		font = titleLabel.font
		subtitleLabel.font = AppKitFontResolver.font(TypographyTokens.MenuRow.subtitle)
		suffixLabel.font = AppKitFontResolver.font(content.suffixStyle == .shortcut
			? TypographyTokens.MenuRow.subtitle : TypographyTokens.MenuRow.title)
		rowHeightConstraint?.constant = rowHeight
		refreshAppearance()
		needsLayout = true
	}

	private func refreshAppearance()
	{
		let foreground: NSColor
		if !isEnabled
		{
			foreground = AppKitColorTokens.settingsTertiaryText
		}
		else
		{
			switch content.role
			{
			case .normal: foreground = AppKitColorTokens.primaryText
			case .destructive: foreground = .systemRed
			case .warning: foreground = .systemOrange
			}
		}
		titleLabel.textColor = foreground
		subtitleLabel.textColor = !isEnabled ? AppKitColorTokens.settingsTertiaryText
			: content.role == .normal ? AppKitColorTokens.secondaryText : foreground
		suffixLabel.textColor = AppKitColorTokens.settingsTertiaryText
		iconView.contentTintColor = content.icon?.isTemplate == true ? foreground : nil
		trailingImageView.contentTintColor = foreground
		let isActive = menuHighlighted || isHovered || isKeyboardFocused || isHighlighted
		iconView.alphaValue = isEnabled ? (isActive ? 1 : 0.75) : 0.5
		trailingImageView.alphaValue = isEnabled ? (isActive ? 1 : 0.75) : 0.5
		if content.indicator == .submenu
		{
			trailingImageView.image = DesktopIcons.image(.chevronRight)
		}
		else if content.indicator == .checkmark, checked
		{
			trailingImageView.image = DesktopIcons.image(.check)
		}
		else
		{
			trailingImageView.image = nil
		}
		trailingImageView.isHidden = trailingImageView.image == nil
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		let iconFrame = NSRect(
			x: Layout.horizontalInset,
			y: bounds.midY - Layout.iconSize / 2,
			width: Layout.iconSize,
			height: Layout.iconSize
		)
		iconView.frame = iconFrame
		trailingImageView.frame = NSRect(
			x: bounds.maxX - Layout.horizontalInset - Layout.iconSize,
			y: iconFrame.minY,
			width: Layout.iconSize,
			height: Layout.iconSize
		)
		let hasLeadingContent = content.icon != nil || content.indicator == .checkbox
		let textX = hasLeadingContent ? iconFrame.maxX + Layout.iconSpacing : Layout.horizontalInset
		let reservesIndicator = content.indicator == .checkmark || content.indicator == .submenu
		let trailing = reservesIndicator ? trailingImageView.frame.minX - Layout.iconSpacing
			: bounds.maxX - Layout.horizontalInset
		let suffixWidth = min(
			max(
				0,
				trailing - textX
			),
			ceil(suffixLabel.cell?.cellSize.width ?? suffixLabel.intrinsicContentSize.width)
		)
		suffixLabel.frame = NSRect(
			x: trailing - suffixWidth,
			y: bounds.midY - Layout.titleLineHeight / 2,
			width: suffixWidth,
			height: Layout.titleLineHeight
		)
		let textEnd = content.suffix.isEmpty ? trailing
			: suffixLabel.frame.minX - Layout.iconSpacing
		titleLabel.frame = NSRect(
			x: textX,
			y: content.subtitle == nil ? bounds.midY - Layout.titleLineHeight / 2
				: Layout.verticalInset,
			width: max(
				0,
				textEnd - textX
			),
			height: Layout.titleLineHeight
		)
		subtitleLabel.frame = NSRect(
			x: textX,
			y: titleLabel.frame.maxY,
			width: max(
				0,
				textEnd - textX
			),
			height: Layout.subtitleLineHeight
		)
	}

	@objc private func invoke()
	{
		guard isEnabled
		else
		{
			return
		}
		onInvoke?()
	}

	override func accessibilityPerformPress() -> Bool
	{
		guard isEnabled, let action
		else
		{
			return false
		}
		return sendAction(
			action,
			to: target
		)
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		super.hitTest(point) == nil ? nil : self
	}

	override func keyDown(with event: NSEvent)
	{
		if onKeyDown?(event) != true
		{
			super.keyDown(with: event)
		}
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		isKeyboardFocused = accepted
		refreshAppearance()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			isKeyboardFocused = false
		}
		refreshAppearance()
		return accepted
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		refreshAppearance()
		if isEnabled
		{
			onHover?()
		}
	}

	override func mouseExited(with event: NSEvent)
	{
		clearHover()
	}

	func clearHover()
	{
		isHovered = false
		refreshAppearance()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshAppearance()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if isEnabled && (menuHighlighted || isHovered || isKeyboardFocused || isHighlighted)
		{
			AppKitColorTokens.rowHighlight.setFill()
			AppKitShapePath.roundedRect(
				bounds,
				radius: ShapeTokens.SidebarMenu.rowRadius,
				curve: ShapeTokens.AccountMenu.cornerCurve
			).fill()
		}
		if content.indicator == .checkbox
		{
			drawCheckbox()
		}
	}

	private func drawCheckbox()
	{
		let rect = NSRect(
			x: Layout.horizontalInset,
			y: bounds.midY - Layout.iconSize / 2,
			width: Layout.iconSize,
			height: Layout.iconSize
		)
		let path = NSBezierPath(
			roundedRect: rect,
			xRadius: 4,
			yRadius: 4
		)
		if checked
		{
			(isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor).setFill()
			path.fill()
			DesktopIcons.draw(
				.check,
				in: rect.insetBy(
					dx: 2,
					dy: 2
				),
				tint: .white
			)
		}
		else
		{
			AppKitColorTokens.secondaryText.withAlphaComponent(0.25).setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
}
