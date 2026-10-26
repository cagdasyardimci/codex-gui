import AppKit

/// Owns the permission summary, artwork and measured composer control presentation.
@MainActor
final class ComposerPermissionButton: DesktopHoverButton
{
	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		cell = ComposerPermissionButtonCell(textCell: "")
		imageScaling = .scaleProportionallyUpOrDown
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Composer.preference)
		imagePosition = .imageLeading
		lineBreakMode = .byTruncatingTail
		cornerRadius = ShapeTokens.Composer
			.controlRadius(forControlHeight: LayoutTokens.composer.controlHeight)
		heightAnchor.constraint(equalToConstant: LayoutTokens.composer.controlHeight)
			.isActive = true
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		render(mode: .askForApproval)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func render(
		mode: ApprovalMode,
		configuredDescription: String? = nil,
		configuredFullAccess: Bool? = nil
	)
	{
		let configured = configuredDescription != nil
		let permissionTitle = configured ? "Configured permissions" : mode.title
		let description = configuredDescription ?? mode.description
		let fullAccess = configuredFullAccess ?? (mode == .fullAccess)
		let tint = fullAccess ? ApprovalPopoverStyle.fullAccess : AppKitColorTokens
			.composerSecondaryText
		title = permissionTitle
		toolTip = "\(permissionTitle): \(description)"
		setAccessibilityLabel("Approval policy: \(permissionTitle)")
		contentTintColor = tint
		attributedTitle = NSAttributedString(
			string: permissionTitle,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.Composer.preference),
				.foregroundColor: tint,
			]
		)
		let symbol: DesktopIcon
		switch mode
		{
		case .askForApproval: symbol = .handRaised
		case .approveForMe: symbol = .shieldCheck
		case .fullAccess: symbol = .warning
		}
		image = fullAccess ? ComposerFooterIcons.fullAccess
			: DesktopIcons.image(
				configured ? .settings : symbol,
				size: LayoutTokens.permission.iconSize
			)
		invalidateIntrinsicContentSize()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.draw(dirtyRect)
		}
	}

	override var intrinsicContentSize: NSSize
	{
		let size = super.intrinsicContentSize
		let titleWidth = (title as NSString).size(withAttributes: [
			.font: font ?? AppKitFontResolver.font(TypographyTokens.Composer.preference),
		]).width
		return NSSize(
			width: (cell as? ComposerPermissionButtonCell)?.requestedWidth(titleWidth: titleWidth)
				?? PermissionControlLayout().requestedWidth(titleWidth: titleWidth),
			height: size.height
		)
	}
}
