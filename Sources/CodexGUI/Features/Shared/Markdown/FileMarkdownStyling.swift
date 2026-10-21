import AppKit

/// Files uses Desktop's reading typography without changing the shared Markdown semantics.
@MainActor
enum FileMarkdownStyling
{
	static func mathFontSize(
		style: MarkdownTextStyle,
		inline: Bool
	) -> CGFloat
	{
		let role = inline && style.heading > 0
			? TypographyTokens.FileMarkdown.heading(level: style.heading)
			: TypographyTokens.FileMarkdown.prose
		return role.size * TypographyTokens.FileMarkdown.mathScale
	}

	static func apply(to content: NSAttributedString) -> NSAttributedString
	{
		let result = NSMutableAttributedString(attributedString: content)
		let fullRange = NSRange(
			location: 0,
			length: content.length
		)
		content.enumerateAttributes(in: fullRange)
		{
			attributes, range, _ in
			if attributes[.markdownInlineCode] as? Bool == true
			{
				// The source attribute still owns selection copy; Files uses bare monospace ink.
				result.removeAttribute(
					.markdownInlineCode,
					range: range
				)
			}
			guard let role = attributes[.markdownParagraphRole] as? String,
					role == "heading" || role == "prose",
					attributes[.markdownThematicBreak] as? Bool != true
			else
			{
				return
			}
			let heading = attributes[.markdownHeadingLevel] as? Int ?? 0
			let typography = heading > 0
				? TypographyTokens.FileMarkdown.heading(level: heading)
				: TypographyTokens.FileMarkdown.prose
			if attributes[.link] == nil, (attributes[.markdownQuoteDepth] as? Int ?? 0) == 0
			{
				result.addAttribute(
					.foregroundColor,
					value: AppKitColorTokens.primaryText,
					range: range
				)
			}
			if attributes[.attachment] == nil,
				attributes[.markdownInlineCode] as? Bool != true,
				let previous = attributes[.font] as? NSFont
			{
				let traits = previous.fontDescriptor.symbolicTraits
				let font = heading > 0
					? AppKitFontResolver.font(
						typography,
						italic: traits.contains(.italic)
					)
					: AppKitFontResolver.font(
						typography.emphasized(traits.contains(.bold)),
						italic: traits.contains(.italic)
					)
				result.addAttribute(
					.font,
					value: font,
					range: range
				)
			}
			guard let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
				.mutableCopy() as? NSMutableParagraphStyle
			else
			{
				return
			}
			paragraph.minimumLineHeight = typography.lineHeight ?? 0
			// Fractions and other inline attachments can exceed the ordinary text line height.
			paragraph.maximumLineHeight = 0
			paragraph.lineSpacing = 0
			paragraph.paragraphSpacing = LayoutTokens.FileMarkdown.linePadding
			let blankLines = attributes[.markdownBlankLinesBefore] as? Int ?? 0
			paragraph.paragraphSpacingBefore = CGFloat(blankLines)
				* ((TypographyTokens.FileMarkdown.prose.lineHeight ?? 0)
					+ LayoutTokens.FileMarkdown.linePadding)
			result.addAttribute(
				.paragraphStyle,
				value: paragraph,
				range: range
			)
		}
		return NSAttributedString(attributedString: result)
	}
}
