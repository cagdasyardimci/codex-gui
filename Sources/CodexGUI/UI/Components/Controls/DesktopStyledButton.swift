import AppKit

/// Complete desktop button presentation. Semantic variants own typography, geometry and states.
@MainActor
class DesktopStyledButton: NSButton
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
		case primary, secondary, destructive, quiet, link, icon, revealingIcon, toggle, menuTrigger
		case nativeDefault, nativeBorderless, nativeLink, nativeInline, nativeProminent, nativeIcon
		case tab(selected: Bool)
		case pairingTab(selected: Bool)
		case settingsHeader(primary: Bool)
		case imageOverlay(light: Bool)
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
	private var dialogFocusIndicator: CAShapeLayer?
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
		if presentation == .nativeDefault
		{
			let native = NSButton(
				title: title,
				target: nil,
				action: nil
			)
			cell = native.cell?.copy() as? NSCell
			frame = native.frame
		}
		self.title = title
		isBordered = false
		setButtonType(usesNativePresentation ? .momentaryPushIn : .momentaryChange)
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
		presentation: Presentation = .nativeInline,
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
			imagePosition = presentation == .nativeIcon ? .imageOnly : .imageLeading
		}
	}

	private var usesNativePresentation: Bool
	{
		[
			Presentation.nativeDefault,
			.nativeBorderless,
			.nativeLink,
			.nativeInline,
			.nativeProminent,
			.nativeIcon
		]
		.contains(presentation)
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
		if usesNativePresentation
		{
			let native = NSButton(
				title: title,
				target: nil,
				action: nil
			)
			if cell is DesktopStyledButtonCell, let nativeCell = native.cell?.copy() as? NSCell
			{
				installPresentationCell(nativeCell)
			}
			bezelStyle = [Presentation.nativeDefault, .nativeBorderless, .nativeLink]
				.contains(presentation)
				? native.bezelStyle : .inline
			isBordered = presentation == .nativeDefault && native.isBordered
			controlSize = [Presentation.nativeDefault, .nativeBorderless, .nativeLink]
				.contains(presentation)
				? native.controlSize : .small
			font = presentation == .nativeDefault ? native.font
				: size == .mini ? .systemFont(ofSize: 10)
				: size == .small ? .systemFont(ofSize: 11)
				: size == .regular ? .systemFont(ofSize: 13)
				: AppKitFontResolver.font(presentation == .nativeProminent
					? TypographyTokens.Controls.prominentButton : TypographyTokens.Controls.button)
			contentTintColor = presentation == .nativeDefault ? native.contentTintColor
				: presentation == .nativeLink ? .linkColor
				: presentation == .nativeProminent ? .labelColor : .secondaryLabelColor
			imagePosition = presentation == .nativeIcon ? .imageOnly
				: image == nil ? native.imagePosition : imagePosition
			if presentation != .nativeDefault
			{
				toolTip = toolTip ?? title
			}
			for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical]
			{
				setContentHuggingPriority(
					native.contentHuggingPriority(for: orientation),
					for: orientation
				)
				setContentCompressionResistancePriority(
					orientation == .horizontal && presentation != .nativeDefault
						? .defaultLow : native
						.contentCompressionResistancePriority(for: orientation),
					for: orientation
				)
			}
			hasDestructiveAction = false
			setAccessibilityRole(presentation == .nativeLink ? .link : .button)
			focusRingType = native.focusRingType
			invalidateIntrinsicContentSize()
			needsDisplay = true
			return
		}
		if !(cell is DesktopStyledButtonCell)
		{
			installPresentationCell(DesktopStyledButtonCell(textCell: title))
		}
		let role: TypographyTokens.Role = presentation == .zoomStep
			? TypographyTokens.Button.zoomStep : (size == .regular
				? TypographyTokens.Button.regular : TypographyTokens.Button.compact)
		font = AppKitFontResolver.font(role)
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
		usesNativePresentation ? super.alignmentRectInsets : NSEdgeInsets()
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
		if usesNativePresentation
		{
			return super.intrinsicContentSize
		}
		let width = ceil((title as NSString).size(withAttributes: [.font: resolvedFont]).width)
		let progress = hasLeadingProgress ? LayoutTokens.Button.progressAllowance : 0
		switch presentation
		{
		case .tab, .pairingTab:
			return NSSize(
				width: width + 18,
				height: LayoutTokens.Button.tabHeight
			)
		case .settingsHeader(let primary):
			return NSSize(
				width: max(
					primary ? LayoutTokens.Settings.headerPrimaryMinimumWidth : 0,
					width + 2 * LayoutTokens.Settings.headerActionHorizontalInset
				),
				height: LayoutTokens.Settings.headerActionHeight
			)
		case .icon, .revealingIcon, .toggle:
			let side = size == .regular
				? LayoutTokens.Button.regularIconSize : LayoutTokens.Button.compactIconSize
			return NSSize(
				width: side,
				height: side
			)
		case .imageOverlay(let light):
			let side = light
				? LayoutTokens.Button.diagramIconSize : LayoutTokens.Button.overlayIconSize
			return NSSize(
				width: side,
				height: side
			)
		case .zoomStep:
			return NSSize(
				width: LayoutTokens.Button.zoomStepSize,
				height: LayoutTokens.Button.zoomStepSize
			)
		default:
			let inset = size == .regular
				? LayoutTokens.Button.regularHorizontalInset : LayoutTokens.Button
				.compactHorizontalInset
			let trailing = presentation == .menuTrigger
				? LayoutTokens.Button.menuChevronSize + LayoutTokens.Button.menuChevronSpacing : 0
			return NSSize(
				width: max(
					size == .regular ? LayoutTokens.Button.regularMinimumWidth : 0,
					width + 2 * inset + progress + trailing
				),
				height: size == .regular
					? LayoutTokens.Button.regularHeight : LayoutTokens.Button.compactHeight
			)
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
		font ?? AppKitFontResolver.font(size == .regular
			? TypographyTokens.Button.regular : TypographyTokens.Button.compact)
	}

	override func layout()
	{
		super.layout()
		refreshDialogFocus()
		loadingIndicator?.frame = NSRect(
			x: LayoutTokens.Button.progressInset,
			y: bounds.midY - LayoutTokens.Button.progressSize / 2,
			width: LayoutTokens.Button.progressSize,
			height: LayoutTokens.Button.progressSize
		)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			loadingIndicator?.stopAnimation(nil)
		}
		super.viewWillMove(toWindow: newWindow)
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
			options: hoverTrackingOptions
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
		return accepted
	}

	private func refreshDialogFocus()
	{
		guard keyboardFocusPolicy == .dialog
		else
		{
			dialogFocusIndicator?.isHidden = true
			return
		}
		if dialogFocusIndicator == nil
		{
			wantsLayer = true
			let indicator = CAShapeLayer()
			indicator.fillColor = nil
			indicator.lineWidth = 2
			indicator.zPosition = 100
			layer?.addSublayer(indicator)
			dialogFocusIndicator = indicator
		}
		guard let indicator = dialogFocusIndicator
		else
		{
			return
		}
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		defer
		{
			CATransaction.commit()
		}
		indicator.isHidden = !isEnabled || window?.firstResponder !== self
		indicator.frame = bounds
		indicator.contentsScale = window?.backingScaleFactor ?? 2
		indicator.path = AppKitShapePath.roundedCGPath(
			bounds.insetBy(
				dx: 2,
				dy: 2
			),
			radius: min(
				8,
				bounds.height / 2 - 2
			),
			curve: ShapeTokens.Connections.curve
		)
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			indicator.strokeColor = NSColor.keyboardFocusIndicatorColor.cgColor
		}
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
		isHovered = true
		needsDisplay = true
	}
	override func mouseExited(with event: NSEvent)
	{
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
		case .icon, .revealingIcon, .zoomStep: ShapeTokens.Button.iconRadius
		case .imageOverlay: bounds.height / 2
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
		let active = isEnabled && (isHovered || isHighlighted)
		let foreground = drawSurface(active: active)
		if case .imageOverlay = presentation
		{
			drawImage(foreground)
			return
		}
		if presentation == .icon || presentation == .revealingIcon || presentation == .toggle
		{
			if isGlyphVisible
			{
				drawImage(foreground)
			}
			return
		}
		if presentation == .menuTrigger
		{
			drawMenuTrigger(foreground)
			return
		}
		let attributes: [NSAttributedString.Key: Any] = [
			.font: resolvedFont,
			.foregroundColor: foreground,
		]
		let measured = (title as NSString).size(withAttributes: attributes)
		let origin = NSPoint(
			x: bounds.midX - measured.width / 2
				+ (hasLeadingProgress ? LayoutTokens.Button.progressAllowance / 2 : 0),
			y: bounds.midY - measured.height / 2
		)
		(title as NSString).draw(
			at: origin,
			withAttributes: attributes
		)
		if presentation == .link && active
		{
			foreground.setFill()
			NSRect(
				x: origin.x,
				y: origin.y,
				width: measured.width,
				height: 1
			).fill()
		}
	}

	private func drawSurface(active: Bool) -> NSColor
	{
		let enabledAlpha: CGFloat = isEnabled ? 1 : 0.4
		let primaryText = AppKitColorTokens.settingsPrimaryText
		switch presentation
		{
		case .nativeDefault, .nativeBorderless, .nativeLink, .nativeInline, .nativeProminent,
				.nativeIcon:
			return contentTintColor ?? .secondaryLabelColor
		case .primary:
			AppKitColorTokens.buttonPrimarySurface.withAlphaComponent(
				!isEnabled ? 0.4 : (active ? 0.8 : 1)
			).setFill()
			outline.fill()
			return AppKitColorTokens.buttonPrimaryText.withAlphaComponent(enabledAlpha)
		case .secondary:
			(active ? AppKitColorTokens.connectionsSecondaryHover
				: AppKitColorTokens.buttonSecondarySurface).setFill()
			outline.fill()
			AppKitColorTokens.buttonSecondaryEdge.withAlphaComponent(
				AppKitColorTokens.buttonSecondaryEdge.alphaComponent * enabledAlpha
			).setStroke()
			outline.lineWidth = ShapeTokens.Button.outlineWidth
			outline.stroke()
			return primaryText.withAlphaComponent(enabledAlpha)
		case .destructive:
			AppKitColorTokens.buttonDestructiveText.withAlphaComponent(
				isEnabled ? (active ? 0.2 : 0.1) : 0.04
			).setFill()
			outline.fill()
			return AppKitColorTokens.buttonDestructiveText.withAlphaComponent(enabledAlpha)
		case .quiet, .icon, .revealingIcon, .link, .zoomStep, .toggle, .menuTrigger:
			if active || (presentation == .toggle && state == .on)
			{
				AppKitColorTokens.settingsSelectorHover.setFill()
				outline.fill()
			}
			if presentation ==
				.zoomStep
			{
				return NSColor.darkGray.withAlphaComponent(enabledAlpha)
			}
			if presentation == .link
			{
				return NSColor.linkColor.withAlphaComponent(enabledAlpha)
			}
			return primaryText.withAlphaComponent(enabledAlpha)
		case .imageOverlay(let light):
			ExpandedImageHeaderDrawing.drawBackground(
				control: self,
				hover: isHovered,
				lightSurface: light
			)
			return ExpandedImageHeaderDrawing.foreground(
				enabled: isEnabled,
				lightSurface: light
			)
		case .tab(let selected):
			if selected || active
			{
				primaryText.withAlphaComponent(selected ? (active ? 0.1 : 0.05) : 0.055).setFill()
				outline.fill()
			}
			return (selected ? primaryText : AppKitColorTokens.settingsTertiaryText)
				.withAlphaComponent(enabledAlpha)
		case .pairingTab(let selected):
			if selected
			{
				AppKitColorTokens.pairingSegmentSelected.setFill(); outline.fill()
			}
			return (selected ? primaryText : AppKitColorTokens.settingsSecondaryText)
				.withAlphaComponent(enabledAlpha)
		case .settingsHeader(let primary):
			let fill = primary ? AppKitColorTokens.buttonPrimarySurface
				: (active ? AppKitColorTokens.connectionsSecondaryHover
					: AppKitColorTokens.settingsHeaderActionSurface)
			fill.withAlphaComponent(!isEnabled ? 0.4 : (primary && active ? 0.8 : 1)).setFill()
			outline.fill()
			if !primary
			{
				AppKitColorTokens.settingsHeaderActionEdge.setStroke()
				outline.lineWidth = 1
				outline.stroke()
			}
			return (primary ? AppKitColorTokens.settingsHeaderPrimaryText : primaryText)
				.withAlphaComponent(enabledAlpha)
		}
	}

	private func drawMenuTrigger(_ tint: NSColor)
	{
		let inset = size == .regular
			? LayoutTokens.Button.regularHorizontalInset : LayoutTokens.Button
			.compactHorizontalInset
		let side = LayoutTokens.Button.menuChevronSize
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingMiddle
		let attributes: [NSAttributedString.Key: Any] = [
			.font: resolvedFont,
			.foregroundColor: tint,
			.paragraphStyle: paragraph
		]
		let height = (title as NSString).size(withAttributes: attributes).height
		(title as NSString).draw(
			in: NSRect(
				x: inset,
				y: bounds.midY - height / 2,
				width: max(
					0,
					bounds.width - 2 * inset - side
						- LayoutTokens.Button.menuChevronSpacing
				),
				height: height
			),
			withAttributes: attributes
		)
		DesktopIcons.draw(
			DesktopIcons.image(.chevronRight),
			in: NSRect(
				x: bounds.maxX - inset - side,
				y: bounds.midY - side / 2,
				width: side,
				height: side
			),
			tint: tint
		)
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
		usesNativePresentation ? super.focusRingMaskBounds : bounds
	}
	override func drawFocusRingMask()
	{
		if usesNativePresentation
		{
			super.drawFocusRingMask()
		}
		else
		{
			outline.fill()
		}
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
