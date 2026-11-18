import AppKit

/// Native toolbar actions shared by Files and Changes; feature owners supply action state.
@MainActor
final class ViewerToolbarButton: DesktopHoverButton
{
	enum Presentation
	{
		case capsule, grouped, groupedDropdown, rootSelector
	}

	var presentation: Presentation = .capsule
	{
		didSet
		{
			updateShadow()
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	static func icon(
		_ title: String,
		image: NSImage,
		target: AnyObject?,
		action: Selector?
	) -> ViewerToolbarButton
	{
		let control = ViewerToolbarButton(
			image: image,
			target: target,
			action: action
		)
		control.presentation = .grouped
		control.imagePosition = .imageOnly
		control.contentTintColor = AppKitColorTokens.secondaryText
		control.toolTip = title
		control.setAccessibilityLabel(title)
		NSLayoutConstraint.activate([
			control.widthAnchor
				.constraint(equalToConstant: ViewerToolbarGroup.Geometry.controlSize),
			control.heightAnchor
				.constraint(equalToConstant: ViewerToolbarGroup.Geometry.controlSize)
		])
		return control
	}

	private let shadowLayer = CALayer()
	private var isGrouped: Bool
	{
		presentation == .grouped || presentation == .groupedDropdown
	}
	private var controlCornerRadius: CGFloat?
	{
		presentation == .rootSelector ? 9 : nil
	}
	override var keyboardFocusCornerRadius: CGFloat
	{
		controlCornerRadius ?? bounds.height / 2
	}
	var showsSelection = false
	var trailingImage: NSImage?
	{
		didSet
		{
			(cell as? ViewerToolbarButtonCell)?.trailingImage = trailingImage
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	// The painted capsule occupies the entire view, including icon-only controls.
	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets(
			top: 0,
			left: 0,
			bottom: 0,
			right: 0
		)
	}

	override var firstBaselineOffsetFromTop: CGFloat
	{
		guard !title.isEmpty, let cell
		else
		{
			return super.firstBaselineOffsetFromTop
		}
		// AppKit reports the baseline within the title rect. The cell centers that rect
		// within the toolbar button's fixed-height presentation.
		let titleRect = cell.titleRect(forBounds: NSRect(
			origin: .zero,
			size: intrinsicContentSize
		))
		return super.firstBaselineOffsetFromTop + titleRect.minY
	}

	override var intrinsicContentSize: NSSize
	{
		if presentation == .groupedDropdown, let cell = cell as? ViewerToolbarButtonCell
		{
			return NSSize(
				width: super.intrinsicContentSize.width + cell.dropdownExtraWidth,
				height: ViewerToolbarGroup.Geometry.controlSize
			)
		}
		if presentation == .grouped
		{
			return NSSize(
				width: title.isEmpty ? ViewerToolbarGroup.Geometry.controlSize
					: super.intrinsicContentSize.width + 16
					+ (trailingImage == nil ? 0 : 16),
				height: ViewerToolbarGroup.Geometry.controlSize
			)
		}
		return NSSize(
			width: title.isEmpty ? 34 : super.intrinsicContentSize.width + 24
				+ (trailingImage == nil ? 0 : 16),
			height: 34
		)
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		usesThemedKeyboardFocus = true
		cell = ViewerToolbarButtonCell(textCell: "")
		wantsLayer = true
		layer?.insertSublayer(
			shadowLayer,
			at: 0
		)
		isBordered = false
		self.setTypographyRole(TypographyTokens.Toolbar.control)
		imagePosition = .imageLeading
		imageScaling = .scaleProportionallyDown
		setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateShadow()
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		updateShadow()
	}

	private func updateShadow()
	{
		shadowLayer.isHidden = isGrouped
		guard !isGrouped
		else
		{
			return
		}
		AppKitShadowRenderer.apply(
			ShadowTokens.fileViewerControl,
			to: shadowLayer,
			in: self,
			cornerRadius: controlCornerRadius ?? bounds.height / 2
		)
	}

	override func drawBackground()
	{
		let selected = showsSelection && state == .on
		let edgeWidth: CGFloat = selected ? 1 / (window?.backingScaleFactor ?? 1) : 1
		let rect = bounds.insetBy(
			dx: edgeWidth / 2,
			dy: edgeWidth / 2
		)
		let radius = controlCornerRadius ?? rect.height / 2
		let path = NSBezierPath(
			roundedRect: rect,
			xRadius: radius,
			yRadius: radius
		)
		let active = isEnabled && (isHighlighted || isHovered)
		if !isGrouped || selected || active
		{
			let fill = selected ? AppKitColorTokens.viewerControlSelection(active: active) :
				active ? hoverBackgroundColor : AppKitColorTokens.controlSurface
			fill.setFill()
			path.fill()
		}
		if selected
		{
			AppKitColorTokens.viewerControlSelectionEdge.setStroke()
			path.lineWidth = edgeWidth
			path.stroke()
		}
		else if !isGrouped
		{
			AppKitColorTokens.subtleEdge.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let selected = showsSelection && state == .on
		contentTintColor = isEnabled
			?
			(selected ? AppKitColorTokens
				.viewerControlSelectedText : (isGrouped && title.isEmpty
					? AppKitColorTokens.secondaryText : AppKitColorTokens.primaryText)) :
			AppKitColorTokens.disabledText
		super.draw(dirtyRect)
	}
}

@MainActor
private final class ViewerToolbarButtonCell: NSButtonCell
{
	private static let dropdownLeadingInset: CGFloat = 12
	private static let dropdownTrailingInset: CGFloat = 6
	private static let dropdownImageSize: CGFloat = 12
	var trailingImage: NSImage?
	var dropdownExtraWidth: CGFloat
	{
		Self.dropdownLeadingInset + Self.dropdownTrailingInset
			+ (trailingImage == nil ? 0 : Self.dropdownImageSize + 4)
	}

	override func draw(
		withFrame cellFrame: NSRect,
		in controlView: NSView
	)
	{
		guard let button = controlView as? ViewerToolbarButton
		else
		{
			super.draw(
				withFrame: cellFrame,
				in: controlView
			)
			return
		}
		if button.presentation == .groupedDropdown
		{
			let titleFrame = NSRect(
				x: cellFrame.minX + Self.dropdownLeadingInset,
				y: cellFrame.minY,
				width: max(
					0,
					cellFrame.width - dropdownExtraWidth
				),
				height: cellFrame.height
			)
			super.draw(
				withFrame: titleFrame,
				in: controlView
			)
			if let trailingImage
			{
				DesktopIcons.draw(
					trailingImage,
					in: NSRect(
						x: cellFrame.maxX - Self.dropdownTrailingInset - Self.dropdownImageSize,
						y: cellFrame.midY - Self.dropdownImageSize / 2,
						width: Self.dropdownImageSize,
						height: Self.dropdownImageSize
					),
					tint: button.isEnabled ? AppKitColorTokens.primaryText : AppKitColorTokens
						.disabledText
				)
			}
			return
		}
		var content = title.isEmpty ? cellFrame : cellFrame.insetBy(
			dx: button.presentation == .grouped ? 8 : 12,
			dy: 0
		)
		if trailingImage != nil
		{
			content.size.width = max(
				0,
				content.width - 16
			)
		}
		super.draw(
			withFrame: content,
			in: controlView
		)
		if let trailingImage
		{
			DesktopIcons.draw(
				trailingImage,
				in: NSRect(
					x: cellFrame.maxX - (button.presentation == .grouped ? 20 : 24),
					y: cellFrame.midY - 6,
					width: 12,
					height: 12
				),
				tint: button.isEnabled ? AppKitColorTokens.primaryText : AppKitColorTokens
					.disabledText
			)
		}
	}
}
