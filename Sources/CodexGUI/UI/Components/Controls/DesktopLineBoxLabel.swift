import AppKit

/// Static native text with the reference's explicit line box and no field-cell side insets.
@MainActor
final class DesktopLineBoxLabel: NSTextField
{
	private let role: TypographyTokens.Role

	init(
		_ text: String,
		role: TypographyTokens.Role
	)
	{
		self.role = role
		super.init(frame: .zero)
		stringValue = text
		self.setTypographyRole(role)
		textColor = AppKitColorTokens.settingsPrimaryText
		isEditable = false
		isSelectable = false
		isBordered = false
		drawsBackground = false
		setAccessibilityRole(.staticText)
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsetsZero
	}

	private var styledText: NSAttributedString
	{
		var attributes = AppKitFontResolver.textAttributes(
			role,
			font: font
		)
		let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
			.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
		paragraph.alignment = alignment
		paragraph.lineBreakMode = .byWordWrapping
		attributes[.paragraphStyle] = paragraph
		attributes[.foregroundColor] = textColor ?? AppKitColorTokens.settingsPrimaryText
		return NSAttributedString(
			string: stringValue,
			attributes: attributes
		)
	}

	override var intrinsicContentSize: NSSize
	{
		let natural = measuredSize(maximumWidth: 10000)
		let fitting = bounds.width > 0 ? measuredSize(maximumWidth: bounds.width) : natural
		return NSSize(
			width: natural.width,
			height: fitting.height
		)
	}

	func measuredSize(maximumWidth: CGFloat) -> NSSize
	{
		let text = styledText
		let fitting = text.boundingRect(
			with: NSSize(
				width: maximumWidth,
				height: 10000
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		)
		return NSSize(
			width: min(
				ceil(fitting.width),
				maximumWidth
			),
			height: max(
				role.lineHeight ?? 0,
				ceil(fitting.height)
			)
		)
	}

	override func setFrameSize(_ newSize: NSSize)
	{
		let previousWidth = bounds.width
		super.setFrameSize(newSize)
		if previousWidth != bounds.width
		{
			invalidateIntrinsicContentSize()
		}
	}

	override func draw(_ dirtyRect: NSRect)
	{
		styledText.draw(
			with: bounds,
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		)
	}
	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}
}
