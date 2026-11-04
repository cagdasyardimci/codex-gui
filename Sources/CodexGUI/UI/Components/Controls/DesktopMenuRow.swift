import AppKit

/// Complete menu item UI; callers provide content and actions rather than their own row layout.
@MainActor
class DesktopMenuRow: NSButton
{
	enum TextPresentation
	{
		case standard, aligned
	}
	private let textPresentation: TextPresentation
	private let titleRole: TypographyTokens.Role
	private let subtitleRole: TypographyTokens.Role
	private let configuration: @MainActor () -> TypographyConfiguration
	private let typographyCenter: NotificationCenter
	private var titleLineHeight: CGFloat = 0
	private var subtitleLineHeight: CGFloat = 0
	private var lastPreferredSize: NSSize?

	private func lineHeight(
		for role: TypographyTokens.Role,
		label: NSTextField,
		fallback: TypographyTokens.Role
	) -> CGFloat
	{
		let config = configuration()
		let metricsRole = role.lineHeightRule == nil ? fallback : role
		// Geometry uses the same native line fitting as retained attributed text.
		let attributes = AppKitFontResolver.textAttributes(
			metricsRole,
			font: label.font,
			configuration: config
		)
		return (attributes[.paragraphStyle] as! NSParagraphStyle).minimumLineHeight
	}

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
	var onPreferredSizeChanged: (() -> Void)?
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
		max(
			Layout.minimumHeight,
			titleLineHeight + 2 * Layout
				.verticalInset + (content.subtitle == nil ? 0 : subtitleLineHeight)
		)
	}
	var preferredSize: NSSize
	{
		let textWidth = max(
			naturalWidth(titleLabel),
			content.subtitle == nil ? 0 : naturalWidth(subtitleLabel)
		)
		let suffixWidth = content.suffix.isEmpty ? 0 : naturalSuffixWidth + Layout.iconSpacing
		return NSSize(
			width: textLeadingInset + textWidth + suffixWidth + textTrailingInset,
			height: rowHeight
		)
	}

	private var textLeadingInset: CGFloat
	{
		Layout.horizontalInset + (content.icon != nil || content.indicator == .checkbox
			? Layout.iconSize + Layout.iconSpacing : 0)
	}

	private var textTrailingInset: CGFloat
	{
		Layout.horizontalInset + (content.indicator == .checkmark || content.indicator == .submenu
			? Layout.iconSize + Layout.iconSpacing : 0)
	}

	private func naturalWidth(_ label: NSTextField) -> CGFloat
	{
		textPresentation == .aligned ? label.attributedStringValue.size().width
			: label.cell?.cellSize.width ?? label.intrinsicContentSize.width
	}

	private var naturalSuffixWidth: CGFloat
	{
		ceil(naturalWidth(suffixLabel))
	}

	let titleLabel: NSTextField
	let subtitleLabel: NSTextField
	let iconView = NSImageView()
	let trailingImageView = NSImageView()
	let suffixLabel: NSTextField
	private(set) var isHovered = false
	private var isKeyboardFocused = false
	private var tracking: NSTrackingArea?
	private var rowHeightConstraint: NSLayoutConstraint?
	private var colorObservation: ThemeColorObservation?
	private typealias Layout = LayoutTokens.MenuRow

	init(
		content: Content,
		textPresentation: TextPresentation = .standard,
		titleRole: TypographyTokens.Role = TypographyTokens.MenuRow.title,
		subtitleRole: TypographyTokens.Role = TypographyTokens.MenuRow.subtitle,
		configuration: @escaping @MainActor () -> TypographyConfiguration =
		{
			.current
		},
		center: NotificationCenter = .default
	)
	{
		self.textPresentation = textPresentation
		self.titleRole = titleRole
		self.subtitleRole = subtitleRole
		self.configuration = configuration
		self.typographyCenter = center
		titleLabel = textPresentation == .aligned ? DesktopTextField(labelWithString: "") :
			NSTextField(labelWithString: "")
		subtitleLabel = textPresentation == .aligned ? DesktopTextField(labelWithString: "") :
			NSTextField(labelWithString: "")
		suffixLabel = textPresentation == .aligned ? DesktopTextField(labelWithString: "") :
			NSTextField(labelWithString: "")
		self.content = content
		super.init(frame: .zero)
		colorObservation = ThemeColorObservation
		{
			[weak self] in self?.refreshAppearance()
		}
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
		titleLabel.setTypographyRole(
			titleRole,
			configuration: configuration,
			center: typographyCenter,
			onUpdate:
			{
				[weak self] in self?.refreshMetrics()
			}
		)
		font = titleLabel.font
		subtitleLabel.setTypographyRole(
			subtitleRole,
			configuration: configuration,
			center: typographyCenter,
			onUpdate:
			{
				[weak self] in self?.refreshMetrics()
			}
		)
		suffixLabel.setTypographyRole(
			content.suffixStyle == .shortcut
				? TypographyTokens.MenuRow.subtitle : TypographyTokens.MenuRow.title,
			configuration: configuration,
			center: typographyCenter
		)
		refreshMetrics()
		refreshAppearance()
		needsLayout = true
	}

	private func refreshMetrics()
	{
		font = titleLabel.font
		titleLineHeight = lineHeight(
			for: titleRole,
			label: titleLabel,
			fallback: TypographyTokens.MenuRow.title
		)
		subtitleLineHeight = content.subtitle == nil ? 0 : lineHeight(
			for: subtitleRole,
			label: subtitleLabel,
			fallback: TypographyTokens.MenuRow.subtitle
		)
		let size = preferredSize
		rowHeightConstraint?.constant = size.height
		invalidateIntrinsicContentSize()
		needsLayout = true
		superview?.needsLayout = true
		if lastPreferredSize != size
		{
			lastPreferredSize = size
			onPreferredSizeChanged?()
		}
	}

	private func refreshAppearance()
	{
		let foreground: NSColor
		switch content.role
		{
		case .normal: foreground = AppKitColorTokens.primaryText
		case .destructive: foreground = AppKitColorTokens.errorText
		case .warning: foreground = AppKitColorTokens.warningText
		}
		alphaValue = isEnabled ? 1 : AppKitColorTokens.disabledMenuOpacity
		titleLabel.textColor = foreground
		subtitleLabel.textColor = content.role == .normal
			? AppKitColorTokens.secondaryText : foreground
		suffixLabel.textColor = AppKitColorTokens.settingsTertiaryText
		iconView.contentTintColor = content.icon?.isTemplate == true ? foreground : nil
		trailingImageView.contentTintColor = foreground
		let isActive = menuHighlighted || isHovered || isKeyboardFocused || isHighlighted
		iconView.alphaValue = isActive ? 1 : AppKitColorTokens.inactiveMenuIconOpacity
		trailingImageView.alphaValue = isActive ? 1 : AppKitColorTokens.inactiveMenuIconOpacity
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
		let textX = textLeadingInset
		let trailing = bounds.maxX - textTrailingInset
		let suffixWidth = min(
			max(
				0,
				trailing - textX
			),
			naturalSuffixWidth
		)
		suffixLabel.frame = labelFrame(
			suffixLabel,
			alignmentRect: NSRect(
				x: trailing - suffixWidth,
				y: bounds.midY - titleLineHeight / 2,
				width: suffixWidth,
				height: titleLineHeight
			)
		)
		let textEnd = content.suffix.isEmpty ? trailing
			: labelRect(suffixLabel).minX - Layout.iconSpacing
		titleLabel.frame = labelFrame(
			titleLabel,
			alignmentRect: NSRect(
				x: textX,
				y: content.subtitle == nil ? bounds.midY - titleLineHeight / 2
					: Layout.verticalInset,
				width: max(
					0,
					textEnd - textX
				),
				height: titleLineHeight
			)
		)
		subtitleLabel.frame = labelFrame(
			subtitleLabel,
			alignmentRect: NSRect(
				x: textX,
				y: labelRect(titleLabel).maxY,
				width: max(
					0,
					textEnd - textX
				),
				height: subtitleLineHeight
			)
		)
	}

	private func labelFrame(
		_ label: NSTextField,
		alignmentRect: NSRect
	) -> NSRect
	{
		textPresentation == .aligned ? label.frame(forAlignmentRect: alignmentRect) : alignmentRect
	}

	private func labelRect(_ label: NSTextField) -> NSRect
	{
		textPresentation == .aligned ? label.alignmentRect(forFrame: label.frame) : label.frame
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
			AppKitColorTokens.accent.setFill()
			path.fill()
			DesktopIcons.draw(
				.check,
				in: rect.insetBy(
					dx: 2,
					dy: 2
				),
				tint: AppKitColorTokens.onAccent
			)
		}
		else
		{
			AppKitColorTokens.uncheckedControlEdge.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}
}
