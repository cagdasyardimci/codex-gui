import AppKit

/// Complete desktop button presentation. Semantic variants own typography, geometry and states.
@MainActor
class DesktopStyledButton: DesktopTooltipButton
{
	enum Size: Equatable
	{
		case mini, small, compact, regular
	}

	enum KeyboardFocusPolicy
	{
		case system, dialog
	}

	var keyboardFocusPolicy: KeyboardFocusPolicy = .system
	{
		didSet
		{
			if keyboardFocusPolicy == .dialog
			{
				refusesFirstResponder = false
				focusRingType = .exterior
			}
			refreshDialogFocus()
		}
	}

	override var acceptsFirstResponder: Bool
	{
		keyboardFocusPolicy == .dialog ? isEnabled : super.acceptsFirstResponder
	}

	override var canBecomeKeyView: Bool
	{
		keyboardFocusPolicy == .dialog
			? isEnabled && window != nil && !isHiddenOrHasHiddenAncestor
			: super.canBecomeKeyView
	}

	enum Presentation: Equatable
	{
		case primary, secondary, dialogPrimary, dialogCancel, dialogOutlined, formAdd, destructive,
				quiet, inlineAction, link, mutedLink, documentation, icon, revealingIcon, toggle,
				menuTrigger
		case sidebarIcon, searchIcon, attachmentRemove
		case tab(selected: Bool)
		case pairingTab(selected: Bool)
		case settingsHeader(primary: Bool)
		case imageOverlay(
			diagram: Bool,
			close: Bool = false
		)
		case zoomStep
	}

	var presentation: Presentation
	{
		didSet
		{
			configurePresentation()
		}
	}
	var size: Size
	{
		didSet
		{
			configurePresentation()
		}
	}
	var showsTrailingChevron = false
	{
		didSet
		{
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}
	private var hasTrailingChevron: Bool
	{
		presentation == .menuTrigger || showsTrailingChevron
	}

	var isLoading = false
	{
		didSet
		{
			invalidateIntrinsicContentSize()
			refreshLoadingIndicator()
			needsLayout = true
			needsDisplay = true
		}
	}
	var hasLeadingProgress: Bool
	{
		get
		{
			isLoading
		}
		set
		{
			isLoading = newValue
		}
	}
	private var loadingIndicator: NSProgressIndicator?
	private let focusIndicator = DesktopControlFocusIndicator()
	private var colorObservation: ThemeColorObservation?
	var hoverTrackingOptions: NSTrackingArea.Options = [
		.mouseEnteredAndExited,
		.activeInKeyWindow,
		.inVisibleRect
	]
	private(set) var isHovered = false
	private var tracking: NSTrackingArea?

	init(
		title: String,
		presentation: Presentation,
		size: Size = .compact
	)
	{
		self.presentation = presentation
		self.size = size
		super.init(frame: .zero)
		colorObservation = ThemeColorObservation
		{
			[weak self] in
			self?.refreshDialogFocus()
			self?.needsDisplay = true
		}
		self.title = title
		isBordered = false
		setButtonType(.momentaryPushIn)
		focusRingType = .exterior
		for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical]
		{
			setContentHuggingPriority(
				.required,
				for: orientation
			)
			setContentCompressionResistancePriority(
				.required,
				for: orientation
			)
		}
		setAccessibilityLabel(title)
		configurePresentation()

	}

	convenience init(
		title: String,
		icon: DesktopIcon? = nil,
		presentation: Presentation = .quiet,
		size: Size = .compact,
		target: AnyObject?,
		action: Selector?
	)
	{
		self.init(
			title: title,
			presentation: presentation,
			size: size
		)
		self.target = target
		self.action = action
		if let icon
		{
			symbol = icon
		}
	}

	var symbol: DesktopIcon?
	{
		didSet
		{
			image = symbol.map
			{
				DesktopIcons.image(
					$0,
					size: LayoutTokens.LayoutDefaults.buttonIconSize
				)
			}
			imagePosition = isIconOnly ? .imageOnly : .imageLeading
		}
	}

	private var isIconOnly: Bool
	{
		switch presentation
		{
		case .icon, .revealingIcon, .toggle, .sidebarIcon, .searchIcon, .imageOverlay,
				.attachmentRemove: true
		default: false
		}
	}

	private var typographyRole: TypographyTokens.Role
	{
		switch presentation
		{
		case .zoomStep: return TypographyTokens.Button.zoomStep
		case .dialogPrimary, .dialogCancel, .dialogOutlined: return TypographyTokens.Button.dialog
		default: break
		}
		return size == .regular ? TypographyTokens.Button.regular : TypographyTokens.Button.compact
	}

	// Styling is owned here even when a caller assigns inherited AppKit font properties.
	final override var font: NSFont?
	{
		get
		{
			AppKitFontResolver.font(
				typographyRole,
				appearance: effectiveAppearance
			)
		}
		set
		{
			super.font = AppKitFontResolver.font(
				typographyRole,
				appearance: effectiveAppearance
			)
		}
	}

	final override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
	}

	final override func sendAction(
		_ action: Selector?,
		to target: Any?
	) -> Bool
	{
		guard isEnabled
		else
		{
			return false
		}
		return super.sendAction(
			action,
			to: target
		)
	}

	override var image: NSImage?
	{
		didSet
		{
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	convenience init(
		icon: DesktopIcon,
		label: String,
		presentation: Presentation = .icon,
		size: Size = .compact
	)
	{
		self.init(
			title: "",
			presentation: presentation,
			size: size
		)
		image = DesktopIcons.image(icon)
		setAccessibilityLabel(label)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private func configurePresentation()
	{
		if !(cell is DesktopStyledButtonCell)
		{
			installPresentationCell(DesktopStyledButtonCell(textCell: title))
		}
		isBordered = false
		imagePosition = isIconOnly ? .imageOnly : image == nil ? .noImage : .imageLeading
		setTypographyRole(typographyRole)
		setContentCompressionResistancePriority(
			isIconOnly ? .required : .defaultLow,
			for: .horizontal
		)
		hasDestructiveAction = presentation == .destructive
		setAccessibilityRole(presentation == .link ? .link : .button)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	private func installPresentationCell(_ replacement: NSCell)
	{
		if let previous = cell as? NSButtonCell, let next = replacement as? NSButtonCell
		{
			next.title = previous.title
			next.target = previous.target
			next.action = previous.action
			next.state = previous.state
			next.image = previous.image
			next.alternateImage = previous.alternateImage
			next.alternateTitle = previous.alternateTitle
			next.keyEquivalent = previous.keyEquivalent
			next.keyEquivalentModifierMask = previous.keyEquivalentModifierMask
			next.tag = previous.tag
			next.isEnabled = previous.isEnabled
			next.isContinuous = previous.isContinuous
			next.allowsMixedState = previous.allowsMixedState
			next.highlightsBy = previous.highlightsBy
			next.showsStateBy = previous.showsStateBy
		}
		cell = replacement
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets()
	}
	override var isEnabled: Bool
	{
		didSet
		{
			refreshDialogFocus()
			needsDisplay = true
		}
	}
	override var state: NSControl.StateValue
	{
		didSet
		{
			needsDisplay = true
		}
	}
	override var title: String
	{
		didSet
		{
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}
	override var intrinsicContentSize: NSSize
	{
		let width = ceil((title as NSString).size(withAttributes: [.font: resolvedFont]).width) +
			(image == nil || isIconOnly ? 0 : LayoutTokens.Button.artworkSize + LayoutTokens.Button
				.contentSpacing)
		let progress = hasLeadingProgress ? LayoutTokens.Button.progressAllowance : 0
		switch presentation
		{
		case .dialogPrimary, .dialogCancel, .dialogOutlined:
			return NSSize(
				width: (title as NSString).size(withAttributes: [.font: resolvedFont]).width
					+ 2 * horizontalInset + 2 * ShapeTokens.Button.outlineWidth + progress,
				height: LayoutTokens.Button.regularHeight
			)
		case .tab, .pairingTab, .formAdd:
			return NSSize(
				width: width + 2 * horizontalInset + progress,
				height: LayoutTokens.Button.tabHeight
			)
		case .settingsHeader(let primary):
			return NSSize(
				width: max(
					primary ? LayoutTokens.Settings.headerPrimaryMinimumWidth : 0,
					width + 2 * horizontalInset + progress + (hasTrailingChevron
						? LayoutTokens.Button.menuChevronSize + LayoutTokens.Button
						.menuChevronSpacing : 0)
				),
				height: LayoutTokens.Settings.headerActionHeight
			)
		case .icon, .revealingIcon, .toggle, .sidebarIcon, .searchIcon:
			let side = iconSide
			return NSSize(
				width: side,
				height: side
			)
		case .attachmentRemove:
			return NSSize(
				width: LayoutTokens.Button.miniIconSize,
				height: LayoutTokens.Button.miniIconSize
			)
		case .imageOverlay(
			let diagram,
			let close
		):
			let side = diagram
				? LayoutTokens.Button.diagramIconSize : LayoutTokens.Button.overlayIconSize
			return NSSize(
				width: diagram && close ? LayoutTokens.Button.diagramCloseWidth : side,
				height: side
			)
		case .zoomStep:
			return NSSize(
				width: LayoutTokens.Button.zoomStepSize,
				height: LayoutTokens.Button.zoomStepSize
			)
		default:
			let inset = horizontalInset
			let trailing = hasTrailingChevron
				? LayoutTokens.Button.menuChevronSize + LayoutTokens.Button.menuChevronSpacing : 0
			return NSSize(
				width: max(
					size == .regular && presentation != .dialogPrimary ? LayoutTokens.Button
						.regularMinimumWidth : 0,
					width + 2 * inset + progress + trailing
				),
				height: size == .regular
					? LayoutTokens.Button.regularHeight : LayoutTokens.Button.compactHeight
			)
		}
	}
	private var horizontalInset: CGFloat
	{
		switch presentation
		{
		case .tab, .pairingTab: LayoutTokens.Button.compactHorizontalInset
		case .settingsHeader: LayoutTokens.Settings.headerActionHorizontalInset
		case .zoomStep, .inlineAction, .documentation: 0
		default: size == .regular ? LayoutTokens.Button.regularHorizontalInset : LayoutTokens.Button
			.compactHorizontalInset
		}
	}

	private var iconSide: CGFloat
	{
		if presentation == .searchIcon
		{
			return LayoutTokens.Button.searchIconSize
		}
		switch size
		{
		case .mini: return LayoutTokens.Button.miniIconSize
		case .small: return LayoutTokens.Button.smallIconSize
		case .compact: return LayoutTokens.Button.compactIconSize
		case .regular: return LayoutTokens.Button.regularIconSize
		}
	}

	var isGlyphVisible: Bool
	{
		presentation != .revealingIcon || DesktopActionRevealState(
			isHovered: isHovered,
			isKeyboardFocused: window?.firstResponder === self
		).isRevealed
	}

	private var resolvedFont: NSFont
	{
		AppKitFontResolver.font(
			typographyRole,
			appearance: effectiveAppearance
		)
	}

	override func layout()
	{
		super.layout()
		refreshDialogFocus()
		loadingIndicator?.frame = isIconOnly
			? NSRect(
				x: bounds.midX - 6,
				y: bounds.midY - 6,
				width: 12,
				height: 12
			)
			: contentLayout(in: bounds).progress ?? .zero
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			loadingIndicator?.stopAnimation(nil)
		}
		isHovered = false
		needsDisplay = true
		super.viewWillMove(toWindow: newWindow)
	}

	override func viewDidHide()
	{
		isHovered = false
		needsDisplay = true
		super.viewDidHide()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		refreshLoadingIndicator()
	}

	private func refreshLoadingIndicator()
	{
		if isLoading && loadingIndicator == nil
		{
			let indicator = NSProgressIndicator()
			indicator.style = .spinning
			indicator.controlSize = .small
			indicator.isDisplayedWhenStopped = false
			indicator.setAccessibilityElement(false)
			addSubview(indicator)
			loadingIndicator = indicator
		}
		loadingIndicator?.stopAnimation(nil)
		loadingIndicator?.isHidden = !isLoading
		if isLoading && window != nil
		{
			loadingIndicator?.startAnimation(nil)
		}
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking,
			options: presentation == .searchIcon ? [
				.mouseEnteredAndExited,
				.activeAlways,
				.inVisibleRect
			] : hoverTrackingOptions
		)
		if presentation == .revealingIcon
		{
			if let window, window.isKeyWindow
			{
				let point = convert(
					window.mouseLocationOutsideOfEventStream,
					from: nil
				)
				isHovered = !isHidden && visibleRect.contains(point)
			}
			else
			{
				isHovered = false
			}
			needsDisplay = true
		}
	}
	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		needsLayout = true
		needsDisplay = true
		needsDisplay = true
		return accepted
	}

	private func refreshDialogFocus()
	{
		let shape: DesktopControlFocusIndicator.Shape?
		if case .imageOverlay = presentation
		{
			shape = .capsule
		}
		else
		{
			shape = keyboardFocusPolicy == .dialog ? .dialog : nil
		}
		focusIndicator.update(
			in: self,
			shape: shape,
			focused: isEnabled && window?.firstResponder === self
		)
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		needsLayout = true
		needsDisplay = true
		return accepted
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		isHovered = true
		needsDisplay = true
	}
	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		isHovered = false
		needsDisplay = true
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshDialogFocus()
		needsDisplay = true
	}

	private var outline: NSBezierPath
	{
		let radius: CGFloat = switch presentation
		{
		case .tab, .pairingTab, .toggle: ShapeTokens.Button.tabRadius
		case .settingsHeader: ShapeTokens.Settings.headerActionRadius
		case .formAdd: ShapeTokens.Button.regularRadius
		case .icon, .revealingIcon, .sidebarIcon, .searchIcon,
				.zoomStep: ShapeTokens.Button.iconRadius
		case .imageOverlay, .attachmentRemove: bounds.height / 2
		default: size == .regular ? ShapeTokens.Button.regularRadius : bounds.height / 2
		}
		let inset = presentation == .secondary ? ShapeTokens.Button.outlineWidth / 2 : 0
		return AppKitShapePath.roundedRect(
			bounds.insetBy(
				dx: inset,
				dy: inset
			),
			radius: radius,
			curve: ShapeTokens.Connections.curve
		)
	}

	fileprivate func drawStyledContents()
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		bounds.clip()
		let groupDisabled = !isEnabled && keyboardFocusPolicy == .dialog &&
			(presentation == .primary || presentation == .secondary)
		if groupDisabled
		{
			NSGraphicsContext.current?.cgContext.setAlpha(0.4)
			NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
		}
		defer
		{
			if groupDisabled
			{
				NSGraphicsContext.current?.cgContext.endTransparencyLayer()
			}
		}
		let active = isEnabled && (isHovered || isHighlighted)
		let foreground = drawSurface(active: active)
		if isIconOnly
		{
			if isGlyphVisible && !isLoading
			{
				drawImage(foreground)
			}
			return
		}
		let layout = contentLayout(in: bounds)
		var attributes = AppKitFontResolver.textAttributes(
			typographyRole,
			font: resolvedFont
		)
		let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
			.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		attributes[.foregroundColor] = foreground
		attributes[.paragraphStyle] = paragraph
		if let image, let rect = layout.image
		{
			DesktopIcons.draw(
				image,
				in: rect,
				tint: foreground
			)
		}
		(title as NSString).draw(
			in: layout.title,
			withAttributes: attributes
		)
		if let rect = layout.chevron
		{
			DesktopIcons.draw(
				DesktopIcons.image(showsTrailingChevron ? .chevronDown : .chevronRight),
				in: rect,
				tint: foreground
			)
		}
		if (presentation == .link && active) || presentation == .mutedLink
		{
			foreground.setFill()
			NSRect(
				x: layout.title.minX,
				y: layout.title.minY,
				width: layout.title.width,
				height: 1
			)
			.fill()
		}
	}

	struct ContentLayout
	{
		let title: NSRect
		let image: NSRect?
		let progress: NSRect?
		let chevron: NSRect?
	}

	// Measurement and painting share the same content slots, including constrained widths.
	func contentLayout(in bounds: NSRect) -> ContentLayout
	{
		let inset = horizontalInset
		let imageWidth = image == nil ? 0 : LayoutTokens.Button.artworkSize
		let imageSpace = imageWidth == 0 ? 0 : imageWidth + LayoutTokens.Button.contentSpacing
		let progressSpace = isLoading ? LayoutTokens.Button.progressAllowance : 0
		let chevronSpace = hasTrailingChevron ? LayoutTokens.Button
			.menuChevronSize + LayoutTokens.Button.menuChevronSpacing : 0
		let available = max(
			0,
			bounds.width - 2 * inset
		)
		let natural = (title as NSString).size(withAttributes: [.font: resolvedFont])
		let titleWidth = min(
			natural.width,
			max(
				0,
				available - imageSpace - progressSpace - chevronSpace
			)
		)
		let width = min(
			available,
			titleWidth + imageSpace + progressSpace + chevronSpace
		)
		let x = alignment == .left ? bounds.minX + inset : alignment == .right ? bounds
			.maxX - inset - width : bounds.midX - width / 2
		func rect(
			_ x: CGFloat,
			_ width: CGFloat,
			_ height: CGFloat
		) -> NSRect
		{
			NSRect(
				x: x,
				y: bounds.midY - height / 2,
				width: width,
				height: height
			)
		}
		return ContentLayout(
			title: rect(
				x + progressSpace + (presentation == .documentation ? 0 : imageSpace),
				titleWidth,
				max(
					natural.height,
					typographyRole.lineHeight ?? 0
				)
			),
			image: imageWidth == 0 ? nil : rect(
				x + progressSpace +
					(presentation == .documentation ? titleWidth + LayoutTokens.Button
						.contentSpacing : 0),
				imageWidth,
				imageWidth
			),
			progress: !isLoading ? nil : rect(
				x,
				LayoutTokens.Button.progressSize,
				LayoutTokens.Button.progressSize
			),
			chevron: chevronSpace == 0 ? nil : rect(
				x + width - LayoutTokens.Button.menuChevronSize,
				LayoutTokens.Button.menuChevronSize,
				LayoutTokens.Button.menuChevronSize
			)
		)
	}

	private func drawSurface(active: Bool) -> NSColor
	{
		let grouped = keyboardFocusPolicy == .dialog &&
			(presentation == .primary || presentation == .secondary)
		let foregroundEnabled = isEnabled || grouped
		let primaryText = AppKitColorTokens.settingsPrimaryText
		switch presentation
		{
		case .sidebarIcon, .searchIcon:
			let selected = state == .on
			if active || selected
			{
				AppKitColorTokens.sidebarButtonSurface(pressed: isHighlighted).setFill()
				outline.fill()
			}
			let color = (active || selected ? AppKitColorTokens.primaryText : AppKitColorTokens
				.secondaryText)
			return AppKitColorTokens.enabledForeground(
				color,
				enabled: foregroundEnabled
			)
		case .primary, .dialogPrimary:
			AppKitColorTokens.primaryButtonSurface(
				enabled: foregroundEnabled,
				active: active
			)
			.setFill()
			outline.fill()
			return AppKitColorTokens.enabledForeground(
				AppKitColorTokens.buttonPrimaryText,
				enabled: foregroundEnabled
			)
		case .dialogOutlined, .dialogCancel:
			(active ? AppKitColorTokens.settingsSelectorHover : AppKitColorTokens
				.buttonSecondarySurface).setFill()
			outline.fill()
			AppKitColorTokens.buttonSecondaryEdge.setStroke()
			outline.lineWidth = ShapeTokens.Button.outlineWidth
			outline.stroke()
			return AppKitColorTokens.enabledForeground(
				primaryText,
				enabled: foregroundEnabled
			)
		case .formAdd:
			AppKitColorTokens.selectedButtonTab(active: active).setFill()
			outline.fill()
			return AppKitColorTokens.enabledForeground(
				AppKitColorTokens.secondaryText,
				enabled: foregroundEnabled
			)
		case .secondary:
			(active ? AppKitColorTokens.settingsSelectorHover
				: (grouped ? AppKitColorTokens.buttonDialogSecondarySurface
					: AppKitColorTokens.buttonSecondarySurface)).setFill()
			outline.fill()
			if !grouped
			{
				AppKitColorTokens.enabledForeground(
					AppKitColorTokens.buttonSecondaryEdge,
					enabled: foregroundEnabled
				).setStroke()
				outline.lineWidth = ShapeTokens.Button.outlineWidth
				outline.stroke()
			}
			return AppKitColorTokens.enabledForeground(
				primaryText,
				enabled: foregroundEnabled
			)
		case .destructive:
			AppKitColorTokens.destructiveButtonSurface(
				enabled: isEnabled,
				active: active
			).setFill()
			outline.fill()
			return AppKitColorTokens.enabledForeground(
				AppKitColorTokens.buttonDestructiveText,
				enabled: foregroundEnabled
			)
		case .quiet, .inlineAction, .icon, .revealingIcon, .link, .mutedLink, .zoomStep, .toggle,
				.menuTrigger, .documentation:
			if active || (presentation == .toggle && state == .on)
			{
				AppKitColorTokens.settingsSelectorHover.setFill()
				outline.fill()
			}
			if presentation ==
				.zoomStep
			{
				return AppKitColorTokens.enabledForeground(
					AppKitColorTokens.imageControlText,
					enabled: foregroundEnabled
				)
			}
			if presentation == .mutedLink || presentation == .documentation
			{
				return AppKitColorTokens.enabledForeground(
					AppKitColorTokens.secondaryText,
					enabled: foregroundEnabled
				)
			}
			if presentation == .link
			{
				return AppKitColorTokens.enabledForeground(
					AppKitColorTokens.accentText,
					enabled: foregroundEnabled
				)
			}
			return AppKitColorTokens.enabledForeground(
				primaryText,
				enabled: foregroundEnabled
			)
		case .attachmentRemove:
			AppKitColorTokens.canvas.setFill()
			outline.fill()
			AppKitColorTokens.primaryText.setFill()
			NSBezierPath(ovalIn: bounds.insetBy(
				dx: 2,
				dy: 2
			)).fill()
			return AppKitColorTokens.buttonPrimaryText
		case .imageOverlay:
			ExpandedImageHeaderDrawing.drawBackground(
				control: self,
				hover: isHovered
			)
			return ExpandedImageHeaderDrawing.foreground(enabled: isEnabled)
		case .tab(let selected):
			if selected
			{
				AppKitColorTokens.selectedButtonTab(active: active).setFill()
				outline.fill()
			}
			else if active
			{
				AppKitColorTokens.settingsSelectorHover.setFill()
				outline.fill()
			}
			let color = selected ? primaryText : AppKitColorTokens.settingsTertiaryText
			return isEnabled ? color : AppKitColorTokens.enabledForeground(
				color,
				enabled: foregroundEnabled
			)
		case .pairingTab(let selected):
			if selected
			{
				AppKitColorTokens.pairingSegmentSelected.setFill(); outline.fill()
			}
			let color = selected ? primaryText : AppKitColorTokens.settingsSecondaryText
			return isEnabled ? color : AppKitColorTokens.enabledForeground(
				color,
				enabled: foregroundEnabled
			)
		case .settingsHeader(let primary):
			AppKitColorTokens.headerButtonSurface(
				primary: primary,
				active: active,
				enabled: isEnabled
			).setFill()
			outline.fill()
			if !primary
			{
				AppKitColorTokens.settingsHeaderActionEdge.setStroke()
				outline.lineWidth = 1
				outline.stroke()
			}
			return AppKitColorTokens.enabledForeground(
				primary ? AppKitColorTokens.settingsHeaderPrimaryText : primaryText,
				enabled: foregroundEnabled
			)
		}
	}

	private func drawImage(_ tint: NSColor)
	{
		guard let image
		else
		{
			return
		}
		let side = LayoutTokens.Button.artworkSize
		DesktopIcons.draw(
			image,
			in: NSRect(
				x: bounds.midX - side / 2,
				y: bounds.midY - side / 2,
				width: side,
				height: side
			),
			tint: tint
		)
	}
	override var focusRingMaskBounds: NSRect
	{
		bounds
	}
	override func drawFocusRingMask()
	{
		outline.fill()
	}
}

@MainActor
private final class DesktopStyledButtonCell: NSButtonCell
{
	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView
	)
	{
		guard let button = controlView as? DesktopStyledButton
		else
		{
			return
		}
		button.drawStyledContents()
	}
}
