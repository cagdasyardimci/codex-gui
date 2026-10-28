import AppKit

/// Removable Plan preference using the shared composer footer geometry.
@MainActor
final class ComposerPlanModeButton: DesktopHoverButton
{
	private let titleFont = AppKitFontResolver.font(TypographyTokens.Composer.plan)
	private let metrics = LayoutTokens.Permission(
		leadingInset: 9,
		trailingInset: 9
	)

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		title = "Plan"
		font = titleFont
		isBordered = false
		bezelStyle = .inline
		controlSize = .small
		imagePosition = .imageLeading
		imageScaling = .scaleNone
		image = ComposerFooterIcons.plan
		contentTintColor = AppKitColorTokens.composerSecondaryText
		attributedTitle = NSAttributedString(
			string: title,
			attributes: [
				.font: titleFont,
				.foregroundColor: AppKitColorTokens.composerSecondaryText,
			]
		)
		cornerRadius = LayoutTokens.composer.controlHeight / 2
		setAccessibilityLabel("Turn off plan mode")
		toolTip = "Turn off plan mode"
		heightAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight)
			.isActive = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var hoverBackgroundColor: NSColor
	{
		AppKitColorTokens.composerMenuRowHover
	}

	override var intrinsicContentSize: NSSize
	{
		let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
		return NSSize(
			width: width + metrics.titleHorizontalInset,
			height: LayoutTokens.composer.controlHeight
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		image = ComposerFooterIcons.removePlan
	}

	override func clearHover()
	{
		super.clearHover()
		image = ComposerFooterIcons.plan
	}

	override func draw(_ dirtyRect: NSRect)
	{
		drawBackground()
		let tint = isEnabled ? AppKitColorTokens.composerSecondaryText : NSColor
			.disabledControlTextColor
		if let image
		{
			DesktopIcons.draw(
				image,
				in: PermissionControlLayout(metrics: metrics).imageRect(in: bounds),
				tint: tint
			)
		}
		let content = NSAttributedString(
			string: title,
			attributes: [
				.font: titleFont,
				.foregroundColor: tint,
			]
		)
		DesktopTextRendering.withFontSmoothingDisabled
		{
			content.draw(at: NSPoint(
				x: bounds.minX + metrics.titleLeadingInset,
				y: bounds.midY - content.size().height / 2
			))
		}
	}
}
