import AppKit

/// Converts prepared Markdown presentation values into immutable native text on the main actor.
@MainActor
enum MarkdownAttributedStringRenderer
{
	static let linkColor = NSColor(name: nil)
	{
		appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
			? NSColor(
				srgbRed: 87.0 / 255,
				green: 133.0 / 255,
				blue: 209.0 / 255,
				alpha: 1
			) : .linkColor
	}

	static let proseColor = NSColor(name: nil)
	{
		appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
			? .white : .labelColor
	}

	static func render(
		_ runs: [MarkdownTextRun],
		imageThumbnails: [String: SourceThumbnailLoader.Thumbnail] = [:]
	) -> NSAttributedString
	{
		let result = NSMutableAttributedString(string: "")
		var richBudget = MarkdownRichBlockBudget()
		let columnWidths = MarkdownTableColumnWidths.measure(runs)
		var tables: [Int: NSTextTable] = [:]
		var cells: [MarkdownTableCell.Identity: NSTextTableBlock] = [:]
		for run in runs
		{
			let paragraph = paragraphStyle(for: run.style)
			if let cell = run.style.tableCell
			{
				let key = cell.identity
				let table = tables[cell.tableID] ?? makeTable(columnCount: cell.columnCount)
				tables[cell.tableID] = table
				let block = cells[key] ?? makeCell(
					cell,
					table: table,
					columnWidths: columnWidths[cell.tableID] ?? []
				)
				cells[key] = block
				paragraph.textBlocks = [block]
				paragraph.alignment = alignment(for: cell.alignment)
			}
			var attributes = decoratedAttributes(
				for: run,
				paragraph: paragraph
			)
			addRichBlockAttachment(
				for: run,
				to: &attributes,
				budget: &richBudget,
				imageThumbnails: imageThumbnails
			)
			result.append(NSAttributedString(
				string: displayText(for: run),
				attributes: attributes
			))
		}
		applyCodeHighlighting(to: result)
		return NSAttributedString(attributedString: result)
	}

	private static func displayText(for run: MarkdownTextRun) -> String
	{
		if run.style.code
		{
			return run.text.replacingOccurrences(
				of: " ",
				with: "\u{00A0}"
			)
		}
		guard run.style.listDepth > 0, !run.style.listContinuation,
				["• ", "◦ ", "▪ ", "☑ ", "☐ "].contains(run.text)
		else
		{
			return run.text
		}
		return String(run.text.dropLast()) + "\t"
	}

	private static func decoratedAttributes(
		for run: MarkdownTextRun,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any]
	{
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font(for: run.style),
			.foregroundColor: foregroundColor(for: run.style),
			.paragraphStyle: paragraph,
		]
		if run.style.listDepth > 0, ["• ", "◦ ", "▪ "].contains(run.text)
		{
			attributes[.font] = NSFont.systemFont(
				ofSize: 14,
				weight: .bold
			)
			if run.text == "• "
			{
				// Enlarge the dot without changing the list's line height or tab position.
				attributes[.strokeWidth] = -7
			}
		}
		if !run.style.code, displayText(for: run) != run.text
		{
			attributes[.markdownSourceText] = run.text
		}
		if run.style.code
		{
			attributes[.markdownInlineCode] = true
			if run.style.codePadding
			{
				attributes[.kern] = -3
				attributes[.markdownSourceText] = ""
			}
			else
			{
				attributes[.markdownInlineCodeSource] = run.text
			}
		}
		if let blockID = run.style.codeBlockID
		{
			attributes[.markdownCodeBlockID] = blockID
			if run.style.codeHeader
			{
				attributes[.markdownCodeHeader] = true
			}
			if let language = run.style.codeLanguage
			{
				attributes[.markdownCodeLanguage] = language
			}
		}
		if run.style.quoteDepth > 0
		{
			attributes[.markdownQuoteDepth] = run.style.quoteDepth
			attributes[.markdownQuoteRailOffsets] = run.style.quoteRailOffsets.isEmpty
				? (0 ..< min(
					run.style.quoteDepth,
					6
				)).map
				{
					$0 * MarkdownMetrics.quoteIndent
				}
				: Array(run.style.quoteRailOffsets.prefix(6))
		}
		if run.style.thematicBreak
		{
			attributes[.markdownThematicBreak] = true
		}
		if run.style.strikethrough
		{
			attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
		}
		if let link = run.style.link, let url = URL(string: link)
		{
			attributes[.link] = url
			attributes[.underlineStyle] = 0
			if run.style.webLinkIcon
			{
				attributes[.attachment] = WebLinkFaviconAttachment(url: url)
				attributes[.markdownSourceText] = ""
			}
			else if run.style.fileLinkIcon
			{
				let attachment = makeFileLinkAttachment()
				attributes[.attachment] = attachment
				attributes[.markdownSourceText] = ""
			}
		}
		return attributes
	}

	private static func makeFileLinkAttachment() -> NSTextAttachment
	{
		let attachment = NSTextAttachment()
		let icon = DesktopIcons.image(
			.code,
			size: 14
		)
		icon.isTemplate = false

		let color = linkColor
		attachment.image = NSImage(
			size: NSSize(
				width: 18,
				height: 14
			),
			flipped: false
		)
		{
			bounds in
			icon.draw(in: NSRect(
				x: 0,
				y: -2.5,
				width: 16,
				height: 19
			))
			color.setFill()
			bounds.fill(using: .sourceAtop)
			return true
		}

		attachment.bounds = NSRect(
			x: 0,
			y: -1.5,
			width: 18,
			height: 14
		)
		return attachment
	}

	private static func addRichBlockAttachment(
		for run: MarkdownTextRun,
		to attributes: inout [NSAttributedString.Key: Any],
		budget: inout MarkdownRichBlockBudget,
		imageThumbnails: [String: SourceThumbnailLoader.Thumbnail]
	)
	{
		if let rich = run.style.richBlock, run.text == "\u{FFFC}"
		{
			let attachment: NSTextAttachment
			switch rich.kind
			{
			case .math:
				attachment = MarkdownRichBlockRenderer.mathAttachment(
					latex: rich.payload,
					source: rich.source,
					budget: &budget
				)
			case .diagram:
				attachment = MarkdownRichBlockRenderer.diagramAttachment(
					code: rich.payload,
					source: rich.source,
					budget: &budget
				)
			case .imageGallery:
				attachment = MarkdownImageGalleryAttachment.make(
					paths: rich.imagePaths,
					source: rich.source,
					thumbnails: imageThumbnails,
					budget: &budget
				)
			}
			attributes[.attachment] = attachment
			attributes[.markdownSourceText] = rich.source
		}
	}

	private static func applyCodeHighlighting(to text: NSMutableAttributedString)
	{
		let fullRange = NSRange(
			location: 0,
			length: text.length
		)
		var blocks: [NSRange] = []
		text.enumerateAttribute(
			.markdownCodeBlockID,
			in: fullRange,
			options: []
		)
		{
			value, range, _ in
			if value != nil
			{
				blocks.append(range)
			}
		}
		for block in blocks
		{
			var header = NSRange()
			guard text.attribute(
				.markdownCodeHeader,
				at: block.location,
				longestEffectiveRange: &header,
				in: block
			) as? Bool == true
			else
			{
				continue
			}
			let range = NSRange(
				location: NSMaxRange(header),
				length: NSMaxRange(block) - NSMaxRange(header)
			)
			guard range.length > 0, text.attribute(
				.attachment,
				at: range.location,
				effectiveRange: nil
			) == nil
			else
			{
				continue
			}
			let source = (text.string as NSString).substring(with: range)
			let language = text.attribute(
				.markdownCodeLanguage,
				at: block.location,
				effectiveRange: nil
			) as? String
			guard let light = CodeSyntaxHighlighter.highlightedCode(
				source,
				language: language,
				dark: false
			), let dark = CodeSyntaxHighlighter.highlightedCode(
				source,
				language: language,
				dark: true
			), light.string == source, dark.string == source
			else
			{
				continue
			}
			applyAdaptiveTokenColors(
				light: light,
				dark: dark,
				to: text,
				at: range.location
			)

		}
	}

	static func applyAdaptiveTokenColors(
		light: NSAttributedString,
		dark: NSAttributedString,
		to text: NSMutableAttributedString,
		at offset: Int
	)
	{
		let fullRange = NSRange(
			location: 0,
			length: light.length
		)
		var start = 0
		var lightRange = NSRange(
			location: 0,
			length: 0
		)
		var darkRange = NSRange(
			location: 0,
			length: 0
		)
		var lightColor = NSColor.labelColor
		var darkColor = NSColor.labelColor
		while start < light.length
		{
			if start >= NSMaxRange(lightRange)
			{
				lightColor = light.attribute(
					.foregroundColor,
					at: start,
					longestEffectiveRange: &lightRange,
					in: fullRange
				) as? NSColor ?? .labelColor
			}
			if start >= NSMaxRange(darkRange)
			{
				darkColor = dark.attribute(
					.foregroundColor,
					at: start,
					longestEffectiveRange: &darkRange,
					in: fullRange
				) as? NSColor ?? .labelColor
			}
			let end = min(
				NSMaxRange(lightRange),
				NSMaxRange(darkRange)
			)
			let color = NSColor(name: nil)
			{
				[lightColor, darkColor] appearance in
				appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
					? darkColor : lightColor
			}
			text.addAttribute(
				.foregroundColor,
				value: color,
				range: NSRange(
					location: offset + start,
					length: end - start
				)
			)
			start = end
		}
	}

	private static func paragraphStyle(for style: MarkdownTextStyle) -> NSMutableParagraphStyle
	{
		let paragraph = NSMutableParagraphStyle()
		let wrapsCharacters = style.codeBlock || style.monospaced
		paragraph.lineBreakMode = wrapsCharacters ? .byCharWrapping : .byWordWrapping
		paragraph.lineSpacing = wrapsCharacters ? LayoutTokens.Markdown.codeLineSpacing
			: (style.listDepth > 0 ? LayoutTokens.Markdown.listLineSpacing
				: LayoutTokens.Markdown.proseLineSpacing)
		paragraph.paragraphSpacing = style.listDepth > 0
			? (style.listEnd ? LayoutTokens.Markdown.listEndSpacing
				: LayoutTokens.Markdown.listParagraphSpacing)
			: LayoutTokens.Markdown.paragraphSpacing
		if style.followedByList
		{
			paragraph.paragraphSpacing = LayoutTokens.Markdown.followedByListSpacing
		}
		if style.heading > 0
		{
			paragraph.paragraphSpacingBefore = style.heading <= 2
				? LayoutTokens.Markdown.majorHeadingTopSpacing : LayoutTokens.Markdown
				.headingTopSpacing
			paragraph.paragraphSpacing = LayoutTokens.Markdown.headingBottomSpacing
		}
		if wrapsCharacters || style.suppressParagraphSpacing
		{
			paragraph.paragraphSpacing = 0
		}
		if style.codeBlockEnd
		{
			paragraph.paragraphSpacing = MarkdownLayoutManager.codeBottomPadding
				+ MarkdownLayoutManager.codeBlockSpacing
		}
		if style.richBlock != nil
		{
			paragraph.alignment = .center
		}
		let quoteIndent = CGFloat(min(
			style.quoteDepth,
			6
		)) * MarkdownLayoutManager.quoteIndent
		let listIndent = CGFloat(min(
			max(
				0,
				style.listDepth - 1
			),
			6
		)) * CGFloat(MarkdownMetrics.listIndent)
		paragraph.firstLineHeadIndent = quoteIndent + listIndent
		paragraph.headIndent = paragraph.firstLineHeadIndent
		if style.listDepth > 0
		{
			paragraph.firstLineHeadIndent += LayoutTokens.Markdown.listFirstLineInset
			paragraph.headIndent += LayoutTokens.Markdown.listTextInset
			paragraph.tabStops = [NSTextTab(
				textAlignment: .left,
				location: paragraph.headIndent
			)]
			if style.listContinuation || style.paragraphContinuation
			{
				paragraph.firstLineHeadIndent = paragraph.headIndent
			}
		}
		if style.codeBlock
		{
			paragraph.firstLineHeadIndent += MarkdownLayoutManager.codeInset
			paragraph.headIndent = paragraph.firstLineHeadIndent
			paragraph.tailIndent = -MarkdownLayoutManager.codeInset
		}
		if style.codeHeader
		{
			paragraph.minimumLineHeight = MarkdownLayoutManager.codeHeaderHeight
			paragraph.maximumLineHeight = MarkdownLayoutManager.codeHeaderHeight
		}
		if style.thematicBreak
		{
			paragraph.minimumLineHeight = 16
			paragraph.maximumLineHeight = 16
			paragraph.paragraphSpacingBefore = LayoutTokens.Markdown.thematicTopSpacing
			paragraph.paragraphSpacing = LayoutTokens.Markdown.thematicBottomSpacing
		}
		if style.tableCell != nil
		{
			paragraph.firstLineHeadIndent = 0
			paragraph.headIndent = 0
			paragraph.lineSpacing = 3
			paragraph.paragraphSpacing = 0
		}
		return paragraph
	}

	private static func font(for style: MarkdownTextStyle) -> NSFont
	{
		let size: CGFloat
		if style.codeHeader
		{
			size = 11
		}
		else if style.code || style.codeBlock || style.monospaced
		{
			size = TypographyTokens.Transcript.code.size
		}
		else
		{
			switch style.heading
			{
			case 1: size = 24
			case 2: size = 20
			case 3: size = 18
			case 4: size = 16
			default: size = TypographyTokens.Transcript.prose.size
			}
		}
		let weight: TypographyTokens.Weight
		if style.heading > 0
		{
			weight = .bold
		}
		else if style.bold
		{
			weight = .semibold
		}
		else if style.code
		{
			weight = .medium
		}
		else
		{
			weight = .regular
		}
		let role = TypographyTokens.Role(
			size: size,
			selection: style.code || style.codeBlock || style.monospaced
				? .monospaced(weight: weight) : .system(weight: weight)
		)
		let base = AppKitFontResolver.font(role)
		return style.italic
			? NSFontManager.shared.convert(
				base,
				toHaveTrait: .italicFontMask
			) : base
	}

	private static func foregroundColor(for style: MarkdownTextStyle) -> NSColor
	{
		if style.thematicBreak
		{
			return .clear
		}
		if style.link != nil
		{
			return linkColor
		}
		return style.quoteDepth > 0 ? .secondaryLabelColor : proseColor
	}

	private static func makeTable(columnCount: Int) -> NSTextTable
	{
		let table = NSTextTable()
		table.numberOfColumns = columnCount
		table.layoutAlgorithm = .fixedLayoutAlgorithm
		table.collapsesBorders = true
		table.setValue(
			100,
			type: .percentageValueType,
			for: .width
		)
		return table
	}

	private static func makeCell(
		_ cell: MarkdownTableCell,
		table: NSTextTable,
		columnWidths: [CGFloat]
	) -> NSTextTableBlock
	{
		let block = NSTextTableBlock(
			table: table,
			startingRow: cell.row,
			rowSpan: cell.rowSpan,
			startingColumn: cell.column,
			columnSpan: cell.columnSpan
		)
		let columns = cell.column ..< min(
			cell.column + cell.columnSpan,
			columnWidths.count
		)
		let width = columns.reduce(CGFloat(0))
		{
			$0 + columnWidths[$1]
		}
		block.setValue(
			width,
			type: .percentageValueType,
			for: .width
		)
		block.setWidth(
			8,
			type: .absoluteValueType,
			for: .padding
		)
		block.setWidth(
			4,
			type: .absoluteValueType,
			for: .padding,
			edge: .minX
		)
		block.setWidth(
			4,
			type: .absoluteValueType,
			for: .padding,
			edge: .maxX
		)
		block.setWidth(
			cell.header ? 1 : 0.5,
			type: .absoluteValueType,
			for: .border,
			edge: .maxY
		)
		block.setBorderColor(.separatorColor)
		block.verticalAlignment = .topAlignment
		return block
	}

	private static func alignment(for alignment: MarkdownTableCell.Alignment) -> NSTextAlignment
	{
		switch alignment
		{
		case .left: .left
		case .center: .center
		case .right: .right
		}
	}
}
