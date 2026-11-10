import AppKit

/// An interactive metadata row in a rich preview, including its hover and focus presentation.
@MainActor
final class DesktopPreviewActionRow: DesktopHoverButton
{
	private let label = NSTextField(wrappingLabelWithString: "")
	private let indicator = NSImageView()
	private let showsIndicator: Bool

	init(
		icon: DesktopIcon,
		showsIndicator: Bool = false
	)
	{
		self.showsIndicator = showsIndicator
		super.init(frame: .zero)
		title = ""
		isBordered = false
		cornerRadius = ShapeTokens.HoverPreview.rowRadius
		cornerCurve = ShapeTokens.HoverPreview.curve
		usesThemedKeyboardFocus = true
		let leading = NSImageView()
		leading.image = DesktopIcons.image(
			icon,
			size: 16
		)
		leading.contentTintColor = AppKitColorTokens.secondaryText
		leading.setAccessibilityElement(false)
		leading.widthAnchor.constraint(equalToConstant: 16).isActive = true
		leading.heightAnchor.constraint(equalToConstant: 20).isActive = true
		label.setTypographyRole(TypographyTokens.Text.detail)
		label.textColor = AppKitColorTokens.primaryText
		label.lineBreakMode = .byCharWrapping
		label.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		label.setAccessibilityElement(false)
		for view in [leading, label]
		{
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			leading.leadingAnchor.constraint(equalTo: leadingAnchor),
			leading.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.leadingAnchor.constraint(
				equalTo: leading.trailingAnchor,
				constant: 6
			),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
			label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
			label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
		])
		if showsIndicator
		{
			indicator.image = DesktopIcons.image(
				.arrowUpRight,
				size: 14
			)
			indicator.contentTintColor = AppKitColorTokens.secondaryText
			indicator.setAccessibilityElement(false)
			indicator.widthAnchor.constraint(equalToConstant: 20).isActive = true
			indicator.heightAnchor.constraint(equalToConstant: 20).isActive = true
			indicator.alphaValue = 0
			indicator.translatesAutoresizingMaskIntoConstraints = false
			addSubview(indicator)
			NSLayoutConstraint.activate([
				indicator.trailingAnchor.constraint(equalTo: trailingAnchor),
				indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
				label.trailingAnchor.constraint(
					equalTo: indicator.leadingAnchor,
					constant: -6
				)
			])
		}
		else
		{
			label.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		}
		heightAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setText(_ text: String)
	{
		label.stringValue = text
	}

	override var hoverTrackingOptions: NSTrackingArea.Options
	{
		[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
	}

	override var isBackgroundHighlighted: Bool
	{
		super.isBackgroundHighlighted || (isEnabled && hasKeyboardFocus)
	}

	override func hoverDidChange()
	{
		super.hoverDidChange()
		indicator.alphaValue = showsIndicator && (isHovered || hasKeyboardFocus) ? 1 : 0
		needsDisplay = true
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		super.hitTest(point) == nil ? nil : self
	}
}
