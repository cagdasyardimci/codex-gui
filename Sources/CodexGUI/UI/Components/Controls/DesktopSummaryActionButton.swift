import AppKit

/// Summary actions preserve native drawing while owning their text/icon hierarchy and geometry.
@MainActor
final class DesktopSummaryActionButton: DesktopAttributedTitleButton
{
	enum Presentation
	{
		case primary, caption, muted, navigationIcon, unavailableAction, unavailableSource
	}

	init(
		title: String,
		image: NSImage? = nil,
		presentation: Presentation,
		target: AnyObject? = nil,
		action: Selector? = nil
	)
	{
		super.init(frame: .zero)
		self.title = title
		self.target = target
		self.action = action
		self.image = image
		isBordered = false
		setAccessibilityLabel(title)
		toolTip = title
		if presentation == .unavailableAction || presentation == .unavailableSource
		{
			isEnabled = false
			imagePosition = .imageOnly
			if presentation == .unavailableSource
			{
				contentTintColor = .tertiaryLabelColor
			}
			NSLayoutConstraint.activate([
				widthAnchor.constraint(equalToConstant: LayoutTokens.Summary.actionSize),
				heightAnchor.constraint(equalToConstant: LayoutTokens.Summary.actionSize),
			])
			return
		}
		alignment = .left
		font = AppKitFontResolver.font(TypographyTokens.Summary.body)
		let color: NSColor
		switch presentation
		{
		case .caption: color = AppKitColorTokens.captionText
		case .muted: color = AppKitColorTokens.mutedText
		default: color = .labelColor
		}
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Summary.body),
				.foregroundColor: color,
			]
		)
		contentTintColor = .labelColor
		imagePosition = presentation == .navigationIcon ? .imageOnly : .imageLeading
		imageScaling = .scaleProportionallyDown
		cell?.lineBreakMode = .byTruncatingTail
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		if presentation == .navigationIcon
		{
			NSLayoutConstraint.activate([
				widthAnchor.constraint(equalToConstant: 18),
				heightAnchor.constraint(equalToConstant: 18),
			])
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
