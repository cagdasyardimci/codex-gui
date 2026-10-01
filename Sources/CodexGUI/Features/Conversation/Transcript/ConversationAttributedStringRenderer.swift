import AppKit

/// Converts prepared Markdown presentation values into immutable native text on the main actor.
@MainActor
enum ConversationAttributedStringRenderer
{
	static func render(_ runs: [ConversationTextRun]) -> NSAttributedString
	{
		let result = NSMutableAttributedString(string: "")
		var richBudget = ConversationRichBlockBudget()
		let columnWidths = tableColumnWidths(in: runs)
		var tables: [Int: NSTextTable] = [:]
		var cells: [CellKey: NSTextTableBlock] = [:]
		for run in runs
		{
			let paragraph = paragraphStyle(for: run.style)
			if let cell = run.style.tableCell
			{
				let key = CellKey(
					tableID: cell.tableID,
					row: cell.row,
					column: cell.column
				)
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
				budget: &richBudget
			)
			result.append(NSAttributedString(
				string: run.text,
				attributes: attributes
			))
		}
		applyCodeHighlighting(to: result)
		return NSAttributedString(attributedString: result)
	}

	private static func decoratedAttributes(
		for run: ConversationTextRun,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any]
	{
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font(for: run.style),
			.foregroundColor: foregroundColor(for: run.style),
			.paragraphStyle: paragraph,
		]
		if run.style.code
		{
			attributes[.conversationInlineCode] = true
		}
		if let blockID = run.style.codeBlockID
		{
			attributes[.conversationCodeBlockID] = blockID
			if run.style.codeHeader
			{
				attributes[.conversationCodeHeader] = true
			}
			if let language = run.style.codeLanguage
			{
				attributes[.conversationCodeLanguage] = language
			}
		}
		if run.style.quoteDepth > 0
		{
			attributes[.conversationQuoteDepth] = run.style.quoteDepth
			attributes[.conversationQuoteRailOffsets] = run.style.quoteRailOffsets.isEmpty
				? (0 ..< min(
					run.style.quoteDepth,
					6
				)).map
				{
					$0 * ConversationMarkdownMetrics.quoteIndent
				}
				: Array(run.style.quoteRailOffsets.prefix(6))
		}
		if run.style.thematicBreak
		{
			attributes[.conversationThematicBreak] = true
		}
		if run.style.strikethrough
		{
			attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
		}
		if let link = run.style.link, let url = URL(string: link)
		{
			attributes[.link] = url
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}
		return attributes
	}

	private static func addRichBlockAttachment(
		for run: ConversationTextRun,
		to attributes: inout [NSAttributedString.Key: Any],
		budget: inout ConversationRichBlockBudget
	)
	{
		if let rich = run.style.richBlock, run.text == "\u{FFFC}"
		{
			let attachment: NSTextAttachment
			switch rich.kind
			{
			case .math:
				attachment = ConversationRichBlockRenderer.mathAttachment(
					latex: rich.payload,
					source: rich.source,
					budget: &budget
				)
			case .diagram:
				attachment = ConversationRichBlockRenderer.diagramAttachment(
					code: rich.payload,
					source: rich.source,
					budget: &budget
				)
			}
			attributes[.attachment] = attachment
			attributes[.conversationSourceText] = rich.source
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
			.conversationCodeBlockID,
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
				.conversationCodeHeader,
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
				.conversationCodeLanguage,
				at: block.location,
				effectiveRange: nil
			) as? String
			guard let light = ConversationCodeHighlighter.highlightedCode(
				source,
				language: language,
				dark: false
			), let dark = ConversationCodeHighlighter.highlightedCode(
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

	private static func applyAdaptiveTokenColors(
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
		var boundaries: Set<Int> = [0, light.length]
		for variant in [light, dark]
		{
			variant.enumerateAttribute(
				.foregroundColor,
				in: fullRange,
				options: []
			)
			{
				_, range, _ in
				boundaries.insert(range.location)
				boundaries.insert(NSMaxRange(range))
			}
		}
		let positions = boundaries.sorted()
		for (start, end) in zip(
			positions,
			positions.dropFirst()
		)
		{
			let lightColor = light.attribute(
				.foregroundColor,
				at: start,
				effectiveRange: nil
			) as? NSColor ?? .labelColor
			let darkColor = dark.attribute(
				.foregroundColor,
				at: start,
				effectiveRange: nil
			) as? NSColor ?? .labelColor
			let color = NSColor(name: nil)
			{
				appearance in
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
		}
	}

	private struct CellKey: Hashable
	{
		let tableID: Int
		let row: Int
		let column: Int
	}

	private static func paragraphStyle(for style: ConversationTextStyle) -> NSMutableParagraphStyle
	{
		let paragraph = NSMutableParagraphStyle()
		let wrapsCharacters = style.codeBlock || style.monospaced
		paragraph.lineBreakMode = wrapsCharacters ? .byCharWrapping : .byWordWrapping
		paragraph.lineSpacing = wrapsCharacters ? 2 : 4
		paragraph.paragraphSpacing = style.listDepth > 0 ? 5 : 10
		if style.heading > 0
		{
			paragraph.paragraphSpacingBefore = style.heading <= 2 ? 16 : 12
			paragraph.paragraphSpacing = 8
		}
		if wrapsCharacters || style.suppressParagraphSpacing
		{
			paragraph.paragraphSpacing = 0
		}
		if style.codeBlockEnd
		{
			paragraph.paragraphSpacing = ConversationMarkdownLayoutManager.codeBottomPadding
				+ ConversationMarkdownLayoutManager.codeBlockSpacing
		}
		if style.richBlock != nil
		{
			paragraph.alignment = .center
		}
		let quoteIndent = CGFloat(min(
			style.quoteDepth,
			6
		)) * ConversationMarkdownLayoutManager.quoteIndent
		let listIndent = CGFloat(min(
			max(
				0,
				style.listDepth - 1
			),
			6
		)) * CGFloat(ConversationMarkdownMetrics.listIndent)
		paragraph.firstLineHeadIndent = quoteIndent + listIndent
		paragraph.headIndent = paragraph.firstLineHeadIndent
		if style.listDepth > 0
		{
			paragraph.headIndent += CGFloat(ConversationMarkdownMetrics.listIndent)
			if style.listContinuation || style.paragraphContinuation
			{
				paragraph.firstLineHeadIndent = paragraph.headIndent
			}
		}
		if style.codeBlock
		{
			paragraph.firstLineHeadIndent += ConversationMarkdownLayoutManager.codeInset
			paragraph.headIndent = paragraph.firstLineHeadIndent
			paragraph.tailIndent = -ConversationMarkdownLayoutManager.codeInset
		}
		if style.codeHeader
		{
			paragraph.minimumLineHeight = ConversationMarkdownLayoutManager.codeHeaderHeight
			paragraph.maximumLineHeight = ConversationMarkdownLayoutManager.codeHeaderHeight
		}
		if style.thematicBreak
		{
			paragraph.minimumLineHeight = 16
			paragraph.maximumLineHeight = 16
			paragraph.paragraphSpacingBefore = 8
			paragraph.paragraphSpacing = 12
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

	private static func font(for style: ConversationTextStyle) -> NSFont
	{
		let size: CGFloat
		if style.codeHeader
		{
			size = 11
		}
		else if style.code || style.codeBlock || style.monospaced
		{
			size = 13
		}
		else
		{
			switch style.heading
			{
			case 1: size = 24
			case 2: size = 20
			case 3: size = 18
			case 4: size = 16
			default: size = 15
			}
		}
		let weight: NSFont.Weight = style.bold || style.heading > 0 ? .bold : .regular
		let base = style.code || style.codeBlock || style.monospaced
			? NSFont.monospacedSystemFont(
				ofSize: size,
				weight: weight
			)
			: NSFont.systemFont(
				ofSize: size,
				weight: weight
			)
		return style.italic
			? NSFontManager.shared.convert(
				base,
				toHaveTrait: .italicFontMask
			) : base
	}

	private static func foregroundColor(for style: ConversationTextStyle) -> NSColor
	{
		if style.thematicBreak
		{
			return .clear
		}
		if style.link != nil
		{
			return .linkColor
		}
		return style.quoteDepth > 0 ? .secondaryLabelColor : .labelColor
	}

	private static func tableColumnWidths(in runs: [ConversationTextRun]) -> [Int: [CGFloat]]
	{
		var cellLengths: [CellKey: Int] = [:]
		var lengths: [Int: [CGFloat]] = [:]
		for run in runs
		{
			guard let cell = run.style.tableCell
			else
			{
				continue
			}
			let key = CellKey(
				tableID: cell.tableID,
				row: cell.row,
				column: cell.column
			)
			cellLengths[key, default: 0] += run.text.count
			if lengths[cell.tableID] == nil
			{
				lengths[cell.tableID] = Array(
					repeating: 32,
					count: cell.columnCount
				)
			}
			// Bound prose preference so short columns retain space at narrow transcript widths.
			var columns = lengths[cell.tableID] ?? []
			columns[cell.column] = max(
				columns[cell.column],
				CGFloat(min(
					64,
					cellLengths[key, default: 0]
				))
			)
			lengths[cell.tableID] = columns
		}
		return lengths.mapValues
		{
			columns in
			let total = columns.reduce(
				0,
				+
			)
			return columns.map
			{
				100 * $0 / max(
					1,
					total
				)
			}
		}
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
		_ cell: ConversationTableCell,
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

	private static func alignment(for alignment: ConversationTableCell.Alignment) -> NSTextAlignment
	{
		switch alignment
		{
		case .left: .left
		case .center: .center
		case .right: .right
		}
	}
}
