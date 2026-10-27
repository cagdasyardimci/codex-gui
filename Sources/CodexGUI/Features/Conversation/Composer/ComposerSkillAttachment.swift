import AppKit

@MainActor
final class ComposerSkillAttachment: NSTextAttachment
{
	let selection: ProjectSkillSelection
	let title: String

	init(
		selection: ProjectSkillSelection,
		title: String,
		appearance: NSAppearance
	)
	{
		self.selection = selection
		self.title = title
		super.init(
			data: nil,
			ofType: nil
		)
		refreshImage(appearance: appearance)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func refreshImage(appearance: NSAppearance)
	{
		let title = self.title
		let font = AppKitFontResolver.font(TypographyTokens.Composer.skillMention)
		var resolvedColor = NSColor.clear
		appearance.performAsCurrentDrawingAppearance
		{
			resolvedColor = AppKitColorTokens.composerSkillMention
				.usingColorSpace(.sRGB) ?? .linkColor
		}
		let color = resolvedColor
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
		let labelSize = (title as NSString).size(withAttributes: attributes)
		let size = NSSize(
			width: 19 + ceil(labelSize.width),
			height: 20
		)
		let icon = DesktopIcons.skillMentionImage()
		image = NSImage(
			size: size,
			flipped: false
		)
		{
			_ in
			let iconRect = NSRect(
				x: 0,
				y: 2,
				width: 16,
				height: 16
			)
			icon.draw(in: iconRect)
			color.setFill()
			iconRect.fill(using: .sourceAtop)
			DesktopTextRendering.withFontSmoothingDisabled
			{
				(title as NSString).draw(
					at: NSPoint(
						x: 19,
						y: (20 - labelSize.height) / 2
					),
					withAttributes: attributes
				)
			}
			return true
		}
		bounds = NSRect(
			x: 0,
			y: -4,
			width: size.width,
			height: size.height
		)
		image?.accessibilityDescription = title
	}
}
