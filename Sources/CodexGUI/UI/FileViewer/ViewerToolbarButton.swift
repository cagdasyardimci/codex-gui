import AppKit

/// Native toolbar actions shared by Files and Changes; feature owners supply action state.
@MainActor
final class ViewerToolbarButton: NSButton
{
	enum Presentation
	{
		case capsule, grouped, rootSelector
	}

	var presentation: Presentation = .capsule
	{
		didSet
		{
			focusRingType = presentation == .grouped ? .none : .default
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
		control.contentTintColor = .secondaryLabelColor
		control.toolTip = title
		control.setAccessibilityLabel(title)
		NSLayoutConstraint.activate([
			control.widthAnchor.constraint(equalToConstant: 28),
			control.heightAnchor.constraint(equalToConstant: 28)
		])
		return control
	}

	private let shadowLayer = CALayer()
	private var cornerRadius: CGFloat?
	{
		presentation == .rootSelector ? 9 : nil
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

	override var intrinsicContentSize: NSSize
	{
		if presentation == .grouped
		{
			return NSSize(
				width: title.isEmpty ? 28 : super.intrinsicContentSize.width + 16
					+ (trailingImage == nil ? 0 : 16),
				height: 28
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
		cell = ViewerToolbarButtonCell(textCell: "")
		wantsLayer = true
		layer?.insertSublayer(
			shadowLayer,
			at: 0
		)
		isBordered = false
		font = .systemFont(ofSize: 13)
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
		shadowLayer.isHidden = presentation == .grouped
		guard presentation != .grouped
		else
		{
			return
		}
		AppKitShadowRenderer.apply(
			ShadowTokens.fileViewerControl,
			to: shadowLayer,
			in: self,
			cornerRadius: cornerRadius ?? bounds.height / 2
		)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		let selected = showsSelection && state == .on
		let rect = bounds.insetBy(
			dx: 0.5,
			dy: 0.5
		)
		let radius = cornerRadius ?? rect.height / 2
		let path = NSBezierPath(
			roundedRect: rect,
			xRadius: radius,
			yRadius: radius
		)
		if presentation != .grouped || selected || isHighlighted
		{
			let fill = selected ? AppKitColorTokens.viewerControlSelection : AppKitColorTokens
				.canvas
			(isHighlighted ? AppKitColorTokens.rowHighlight : fill).setFill()
			path.fill()
		}
		if presentation != .grouped
		{
			AppKitColorTokens.subtleEdge.setStroke()
			path.lineWidth = 1
			path.stroke()
		}
		contentTintColor = isEnabled
			? (selected ? .systemBlue : (presentation == .grouped && title.isEmpty
					? AppKitColorTokens.secondaryText : AppKitColorTokens.primaryText)) :
			.disabledControlTextColor
		super.draw(dirtyRect)
	}
}

@MainActor
private final class ViewerToolbarButtonCell: NSButtonCell
{
	var trailingImage: NSImage?

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
				tint: button.isEnabled ? AppKitColorTokens.primaryText : .disabledControlTextColor
			)
		}
	}
}
