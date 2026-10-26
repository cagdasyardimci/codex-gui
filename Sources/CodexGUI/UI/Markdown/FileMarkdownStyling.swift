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
		var omittedRanges: [NSRange] = []
		let fullRange = NSRange(
			location: 0,
			length: content.length
		)
		content.enumerateAttributes(in: fullRange)
		{
			attributes, range, _ in
			let inlineCode = attributes[.markdownInlineCode] as? Bool == true
			if (attributes[.attachment] != nil && attributes[.link] != nil
				&& attributes[.markdownSourceText] as? String == "")
				|| (inlineCode && attributes[.markdownSourceText] as? String == "")
			{
				omittedRanges.append(range)
				return
			}
			if inlineCode
			{
				// The source attribute still owns selection copy; Files uses bare monospace ink.
				result.removeAttribute(
					.markdownInlineCode,
					range: range
				)
			}
			result.addAttribute(
				.markdownFilePreview,
				value: true,
				range: range
			)
			if inlineCode
			{
				result.addAttribute(
					.font,
					value: AppKitFontResolver
						.font(TypographyTokens.FileMarkdown.inlineCode),
					range: range
				)
				result.addAttribute(
					.foregroundColor,
					value: AppKitColorTokens.primaryText,
					range: range
				)
			}
			if attributes[.markdownParagraphRole] as? String == "code"
			{
				styleCode(
					attributes: attributes,
					range: range,
					in: result
				)
				return
			}
			guard let role = attributes[.markdownParagraphRole] as? String,
					role == "heading" || role == "prose" || role == "list",
					attributes[.markdownThematicBreak] as? Bool != true
			else
			{
				return
			}
			let heading = attributes[.markdownHeadingLevel] as? Int ?? 0
			let typography = heading > 0
				? TypographyTokens.FileMarkdown.heading(level: heading)
				: TypographyTokens.FileMarkdown.prose
			if attributes[.link] == nil,
				heading > 0 || (attributes[.markdownQuoteDepth] as? Int ?? 0) == 0
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
			// Source block identities keep adjacent, identically styled blocks separate.
			// A raw HTML block can still contain several source lines in one range; its
			// leading blank lines belong only to the first line of that block.
			let text = (content.string as NSString).substring(with: range) as NSString
			var start = 0
			while start < text.length
			{
				let line = text.paragraphRange(for: NSRange(
					location: start,
					length: 0
				))
				if start > 0
				{
					let continuation = paragraph.mutableCopy() as! NSMutableParagraphStyle
					continuation.paragraphSpacingBefore = 0
					result.addAttribute(
						.paragraphStyle,
						value: continuation,
						range: NSRange(
							location: range.location + start,
							length: line.length
						)
					)
				}
				start = NSMaxRange(line)
			}
		}
		for range in omittedRanges.reversed()
		{
			result.deleteCharacters(in: range)
		}
		styleLinks(in: result)
		return NSAttributedString(attributedString: result)
	}
	private static func styleCode(
		attributes: [NSAttributedString.Key: Any],
		range: NSRange,
		in result: NSMutableAttributedString
	)
	{
		let header = attributes[.markdownCodeHeader] as? Bool == true
		let fenced = attributes[.markdownCodeFenced] as? Bool == true
		result.addAttribute(
			.font,
			value: AppKitFontResolver.font(TypographyTokens.FileMarkdown.fencedCode),
			range: range
		)
		result.addAttribute(
			.foregroundColor,
			value: AppKitColorTokens.primaryText,
			range: range
		)
		guard let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
			.mutableCopy() as? NSMutableParagraphStyle
		else
		{
			return
		}
		paragraph.firstLineHeadIndent = max(
			0,
			paragraph.firstLineHeadIndent - MarkdownLayoutManager.codeInset
		)
		paragraph.headIndent = max(
			0,
			paragraph.headIndent - MarkdownLayoutManager.codeInset
		)
		paragraph.tailIndent = 0
		let headerHeight: CGFloat = fenced
			? DesktopOutputCard.TextKitPresentation.fileCode.headerHeight : 1
		paragraph.minimumLineHeight = header ? headerHeight : 16.8
		paragraph.maximumLineHeight = header ? headerHeight : 16.8
		paragraph.lineSpacing = header ? 0 : LayoutTokens.FileMarkdown.linePadding
		paragraph.paragraphSpacing = !header && fenced && paragraph.paragraphSpacing > 0
			? DesktopOutputCard.TextKitPresentation.fileCode.blockSpacing : 0
		let blankLines = attributes[.markdownBlankLinesBefore] as? Int ?? 0
		paragraph.paragraphSpacingBefore = header ? CGFloat(blankLines)
			* ((TypographyTokens.FileMarkdown.prose.lineHeight ?? 0)
				+ LayoutTokens.FileMarkdown.linePadding) : 0
		if header, fenced, range.location > 0, paragraph.paragraphSpacingBefore > 0
		{
			// The language label draws at the header line-fragment origin, which includes
			// paragraphSpacingBefore. Keep source separation outside that header fragment.
			let previousRange = (result.string as NSString).paragraphRange(for: NSRange(
				location: range.location - 1,
				length: 1
			))
			if let previous = (result.attribute(
				.paragraphStyle,
				at: previousRange.location,
				effectiveRange: nil
			) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
			{
				previous.paragraphSpacing += paragraph.paragraphSpacingBefore
				result.addAttribute(
					.paragraphStyle,
					value: previous,
					range: previousRange
				)
				paragraph.paragraphSpacingBefore = 0
			}
		}
		result.addAttribute(
			.paragraphStyle,
			value: paragraph,
			range: range
		)
	}

	private static func styleLinks(in result: NSMutableAttributedString)
	{
		let fullRange = NSRange(
			location: 0,
			length: result.length
		)
		let text = result.string as NSString
		result.enumerateAttribute(
			.link,
			in: fullRange
		)
		{
			value, range, _ in
			guard value != nil
			else
			{
				return
			}
			// A paragraph separator inherited from a link must not underline the rest of its line.
			for index in range.location ..< NSMaxRange(range) where text.character(at: index) == 10
			{
				let separator = NSRange(
					location: index,
					length: 1
				)
				result.removeAttribute(
					.link,
					range: separator
				)
				result.removeAttribute(
					.underlineStyle,
					range: separator
				)
			}
		}
		guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link
			.rawValue)
		else
		{
			return
		}
		for match in detector.matches(
			in: result.string,
			range: fullRange
		)
		{
			guard let url = match.url, url.scheme == "mailto",
					result.attribute(
					.link,
					at: match.range.location,
					effectiveRange: nil
					) == nil,
					result.attribute(
					.markdownParagraphRole,
					at: match.range.location,
					effectiveRange: nil
					) as? String != "code",
					result.attribute(
					.markdownInlineCodeSource,
					at: match.range.location,
					effectiveRange: nil
					) == nil
			else
			{
				continue
			}
			result.addAttribute(
				.link,
				value: url,
				range: match.range
			)
			result.addAttribute(
				.foregroundColor,
				value: MarkdownAttributedStringRenderer.linkColor,
				range: match.range
			)
		}
	}

}
