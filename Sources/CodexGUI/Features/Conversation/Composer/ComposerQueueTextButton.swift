import AppKit

@MainActor
final class ComposerQueueTextButton: DesktopHoverButton
{
	enum Presentation
	{
		case action, preview
	}
	static let actionHeight: CGFloat = 24
	static let iconSize: CGFloat = 14
	private let presentation: Presentation
	private let fixedWidth: CGFloat?
	private var contentWidth: NSLayoutConstraint?

	init(
		title: String = "",
		icon: DesktopIcon? = nil,
		presentation: Presentation = .action,
		width: CGFloat? = nil,
		imageVerticalOffset: CGFloat = 0
	)
	{
		self.presentation = presentation
		fixedWidth = width
		super.init(frame: .zero)
		controlTooltip.presentation.style = .capsule
		self.imageVerticalOffset = imageVerticalOffset
		isBordered = false
		bezelStyle = .inline
		setButtonType(.momentaryPushIn)
		update(
			title: title,
			icon: icon
		)
		if presentation == .action
		{
			contentWidth = widthAnchor.constraint(equalToConstant: intrinsicContentSize.width)
			contentWidth?.isActive = true
			heightAnchor.constraint(equalToConstant: Self.actionHeight).isActive = true
		}
		else
		{
			highlightsOnHover = false
			alignment = .left
			lineBreakMode = .byTruncatingTail
			cell?.usesSingleLineMode = true
			setAccessibilityRole(.staticText)
			setAccessibilityLabel(title)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func update(
		title: String,
		icon: DesktopIcon? = nil
	)
	{
		self.title = title
		image = icon.map
		{
			DesktopIcons.image(
				$0,
				size: Self.iconSize
			)
		}
		imagePosition = icon == nil ? .noImage : title.isEmpty ? .imageOnly : .imageLeading
		font = .systemFont(ofSize: presentation == .preview ? 14 : 13)
		contentTintColor = presentation == .preview ? AppKitColorTokens.composerPrimaryText
			: AppKitColorTokens.composerSecondaryText
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = presentation == .preview ? 20 : 18
		paragraph.maximumLineHeight = paragraph.minimumLineHeight
		paragraph.lineBreakMode = .byTruncatingTail
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: font!,
				.foregroundColor: contentTintColor!,
				.paragraphStyle: paragraph
			]
		)
		if presentation == .preview
		{
			setAccessibilityLabel(title)
		}
		contentWidth?.constant = intrinsicContentSize.width
		invalidateIntrinsicContentSize()
	}

	override var intrinsicContentSize: NSSize
	{
		guard presentation == .action
		else
		{
			return super.intrinsicContentSize
		}
		let width = fixedWidth ?? (imagePosition == .imageOnly ? Self.actionHeight
			:
			ceil((title as NSString)
				.size(withAttributes: [.font: font ?? .systemFont(ofSize: 13)]).width) + 16
			+ (imagePosition == .imageLeading ? 20 : 0))
		return NSSize(
			width: width,
			height: Self.actionHeight
		)
	}

	var highlightsOnHover = true
	var onHover: (() -> Void)?
	var menuIsOpen = false
	{
		didSet
		{
			needsDisplay = true
		}
	}
	override func clearHover()
	{
		super.clearHover()
		highlight(false)
	}

	var hoverTooltipText: String?
	{
		get
		{
			toolTip
		}
		set
		{
			toolTip = newValue; setAccessibilityHelp(newValue)
		}
	}

	override func mouseDown(with event: NSEvent)
	{
		controlTooltip.dismiss()
		super.mouseDown(with: event)
		clearHover()
	}

	override var hoverTrackingOptions: NSTrackingArea.Options
	{
		[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
	}

	override var synchronizesHoverOnTrackingUpdate: Bool
	{
		true
	}

	override var hoverBackgroundColor: NSColor
	{
		AppKitColorTokens.composerMenuRowHover
	}

	override var isBackgroundHighlighted: Bool
	{
		highlightsOnHover && isEnabled && (isHighlighted || isHovered || menuIsOpen)
	}

	override func hoverDidChange()
	{
		if !isHovered
		{
			controlTooltip.dismiss()
		}
	}

	override func drawBackground()
	{
		cornerRadius = bounds.height / 2
		super.drawBackground()
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		onHover?()

	}
	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		setHovered(false)
	}

	var imageVerticalOffset: CGFloat = 0
	{
		didSet
		{
			needsDisplay = true
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1 : 0.4)
		drawBackground()
		if imagePosition == .imageOnly, let image
		{
			DesktopIcons.draw(
				image,
				in: NSRect(
					x: bounds.midX - Self.iconSize / 2,
					y: bounds.midY - Self.iconSize / 2,
					width: Self.iconSize,
					height: Self.iconSize
				),
				tint: contentTintColor ?? AppKitColorTokens.composerSecondaryText
			)
			return
		}
		let title = NSMutableAttributedString(attributedString: attributedTitle)
		for separator in ["\r\n", "\n", "\r", "\u{2028}", "\u{2029}"]
		{
			title.mutableString.replaceOccurrences(
				of: separator,
				with: " ",
				range: NSRange(
					location: 0,
					length: title.length
				)
			)
		}
		var textX: CGFloat = 0
		if imagePosition == .imageLeading, let image
		{
			DesktopIcons.draw(
				image,
				in: NSRect(
					x: 9,
					y: bounds.midY - Self.iconSize / 2 + imageVerticalOffset,
					width: Self.iconSize,
					height: Self.iconSize
				),
				tint: contentTintColor ?? AppKitColorTokens.composerSecondaryText
			)
			textX = 27
		}
		DesktopTextRendering.withFontSmoothingDisabled
		{
			title.draw(in: NSRect(
				x: textX,
				y: bounds.midY - title.size().height / 2,
				width: max(
					0,
					bounds.width - textX
				),
				height: title.size().height
			))
		}
	}
}
