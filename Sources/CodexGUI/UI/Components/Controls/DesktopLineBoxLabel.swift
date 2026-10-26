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
		font = AppKitFontResolver.font(role)
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
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = alignment
		paragraph.minimumLineHeight = role.lineHeight ?? 0
		paragraph.maximumLineHeight = role.lineHeight ?? 0
		paragraph.lineBreakMode = .byWordWrapping
		return NSAttributedString(
			string: stringValue,
			attributes: [
				.font: font ?? AppKitFontResolver.font(role),
				.foregroundColor: textColor ?? AppKitColorTokens.settingsPrimaryText,
				.paragraphStyle: paragraph,
			]
		)
	}

	override var intrinsicContentSize: NSSize
	{
		let text = styledText
		let fitting = text.boundingRect(
			with: NSSize(
				width: bounds.width > 0 ? bounds.width : 10000,
				height: 10000
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		)
		return NSSize(
			width: ceil(text.size().width),
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
			preferredMaxLayoutWidth = bounds.width
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
