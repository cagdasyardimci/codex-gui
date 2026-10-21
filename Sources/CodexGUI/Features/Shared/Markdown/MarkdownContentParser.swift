import Foundation
import Markdown

/// Parses CommonMark/GFM off the main actor into native presentation values.
enum MarkdownContentParser
{
	static func parse(
		_ body: String,
		markdown: Bool,
		preserveSoftBreaks: Bool = false,
		imageBaseDirectory: URL? = nil
	) -> ParsedMarkdownContent
	{
		guard markdown
		else
		{
			return ParsedMarkdownContent(
				runs: [MarkdownTextRun(
					text: body,
					style: MarkdownTextStyle(monospaced: true)
				)],
				codeBlocks: [],
				codeBlockRanges: [],
				plainTextBoundaries: []
			)
		}

		let initialDocument = Document(
			parsing: body,
			options: [.disableSmartOpts]
		)
		let inlineMath = MarkdownInlineMathParser.prepare(
			body,
			document: initialDocument
		)
		let document = inlineMath.blocks.isEmpty ? initialDocument : Document(
			parsing: inlineMath.source,
			options: [.disableSmartOpts]
		)
		var builder = PresentationBuilder(
			source: body,
			preserveSoftBreaks: preserveSoftBreaks,
			imageBaseDirectory: imageBaseDirectory,
			inlineMath: inlineMath.blocks
		)
		builder.appendBlocks(
			document.children,
			style: MarkdownTextStyle()
		)
		return builder.content
	}

	private struct PresentationBuilder
	{
		let sourceBytes: [UInt8]
		let sourceLineOffsets: [Int]
		let preserveSoftBreaks: Bool
		let imageBaseDirectory: URL?
		let inlineMath: [Character: MarkdownInlineMathParser.Block]
		var runs: [MarkdownTextRun] = []
		var codeBlocks: [String] = []
		var codeBlockRanges: [NSRange] = []
		var textLength = 0
		var tableCount = 0
		var paragraphStart = 0
		var paragraphContinuation = false
		var plainTextBoundaries: [MarkdownPlainTextBoundary] = []
		var plainTextListCount = 0
		var currentPlainTextList: Int?
		var previousPlainTextList: Int?

		init(
			source: String,
			preserveSoftBreaks: Bool,
			imageBaseDirectory: URL?,
			inlineMath: [Character: MarkdownInlineMathParser.Block]
		)
		{
			let bytes = Array(source.utf8)
			sourceBytes = bytes
			sourceLineOffsets = [0] + bytes.indices.compactMap
			{
				bytes[$0] == 10 ? $0 + 1 : nil
			}
			self.preserveSoftBreaks = preserveSoftBreaks
			self.imageBaseDirectory = imageBaseDirectory
			self.inlineMath = inlineMath
		}

		var content: ParsedMarkdownContent
		{
			ParsedMarkdownContent(
				runs: runs,
				codeBlocks: codeBlocks,
				codeBlockRanges: codeBlockRanges,
				plainTextBoundaries: plainTextBoundaries
			)
		}

		mutating func appendBlocks(
			_ children: MarkupChildren,
			style: MarkdownTextStyle
		)
		{
			var imagePaths: [String] = []
			var imageSources: [String] = []
			func flushImages()
			{
				guard !imagePaths.isEmpty
				else
				{
					return
				}
				var imageStyle = style
				imageStyle.richBlock = MarkdownRichBlock(
					kind: .imageGallery,
					source: imageSources.joined(separator: "\n\n"),
					payload: "",
					imagePaths: imagePaths
				)
				beginParagraph(
					style: imageStyle,
					marker: ""
				)
				append(
					"\u{FFFC}",
					style: imageStyle
				)
				imagePaths.removeAll()
				imageSources.removeAll()
			}
			for child in children
			{
				if let paragraph = child as? Paragraph,
					let images = imagesOnly(paragraph)
				{
					imagePaths.append(contentsOf: images.paths)
					imageSources.append(images.source)
					continue
				}
				flushImages()
				appendBlock(
					child,
					style: style
				)
			}
			flushImages()
		}

		func imagesOnly(_ paragraph: Paragraph) -> (paths: [String], source: String)?
		{
			var paths: [String] = []
			for inline in paragraph.children
			{
				switch inline
				{
				case let image as Image:
					guard let path = localImagePath(image)
					else
					{
						return nil
					}
					paths.append(path)
				case is SoftBreak, is LineBreak:
					break
				case let text as Markdown.Text
					where text.string.trimmingCharacters(in: .whitespaces).isEmpty:
					break
				default:
					return nil
				}
			}
			guard !paths.isEmpty, let source = sourceText(of: paragraph)
			else
			{
				return nil
			}
			return (paths, source)
		}

		func localImagePath(_ image: Image) -> String?
		{
			guard let path = image.source
			else
			{
				return nil
			}
			if LocalAttachmentURL.resolve(path) != nil || InlineImageData.isDataURL(path)
			{
				return path
			}
			guard let imageBaseDirectory, !path.isEmpty, !path.hasPrefix("//"),
					URL(string: path)?.scheme == nil
			else
			{
				return nil
			}
			return URL(
				fileURLWithPath: path,
				relativeTo: imageBaseDirectory
			).standardizedFileURL.path
		}

		mutating func appendBlock(
			_ block: any Markup,
			style: MarkdownTextStyle,
			marker: String = ""
		)
		{
			switch block
			{
			case let paragraph as Paragraph:
				if let math = displayMath(in: paragraph)
				{
					var mathStyle = style
					mathStyle.richBlock = math
					beginParagraph(
						style: mathStyle,
						marker: marker
					)
					append(
						"\u{FFFC}",
						style: mathStyle
					)
					return
				}
				beginParagraph(
					style: style,
					marker: marker
				)
				appendInlines(
					paragraph.children,
					style: style
				)
			case let heading as Heading:
				var headingStyle = style
				headingStyle.heading = heading.level
				beginParagraph(
					style: headingStyle,
					marker: marker
				)
				appendInlines(
					heading.children,
					style: headingStyle
				)
			case let code as CodeBlock:
				appendCodeBlock(
					code,
					style: style,
					marker: marker
				)
			case let quote as BlockQuote:
				var quoteStyle = style
				quoteStyle.quoteRailOffsets.append(
					style.listDepth * MarkdownMetrics.listIndent
						+ style.quoteDepth * MarkdownMetrics.quoteIndent
				)
				quoteStyle.quoteDepth += 1
				if !marker.isEmpty
				{
					beginParagraph(
						style: style,
						marker: marker
					)
				}
				appendBlocks(
					quote.children,
					style: quoteStyle
				)
			case let list as UnorderedList:
				appendContainerMarker(
					marker,
					style: style
				)
				appendList(
					list.children,
					startIndex: nil,
					style: style
				)
			case let list as OrderedList:
				appendContainerMarker(
					marker,
					style: style
				)
				appendList(
					list.children,
					startIndex: list.startIndex,
					style: style
				)
			case let table as Table:
				appendContainerMarker(
					marker,
					style: style
				)
				appendTable(
					table,
					style: style
				)
			case is ThematicBreak:
				var ruleStyle = style
				ruleStyle.thematicBreak = true
				beginParagraph(
					style: ruleStyle,
					marker: marker
				)
				append(
					"\u{FFFC}",
					style: ruleStyle
				)
			case let html as HTMLBlock:
				beginParagraph(
					style: style,
					marker: marker
				)
				append(
					html.rawHTML,
					style: style
				)
			default:
				appendContainerMarker(
					marker,
					style: style
				)
				appendBlocks(
					block.children,
					style: style
				)
			}
		}

		mutating func appendList(
			_ children: MarkupChildren,
			startIndex: UInt?,
			style: MarkdownTextStyle
		)
		{
			if let last = runs.last, last.style.listDepth == 0,
				last.style.heading == 0, !last.style.codeBlock,
				last.style.quoteDepth == style.quoteDepth
			{
				for index in paragraphStart ..< runs.count
				{
					var precedingStyle = runs[index].style
					precedingStyle.followedByList = true
					runs[index] = MarkdownTextRun(
						text: runs[index].text,
						style: precedingStyle
					)
				}
			}
			let enclosingList = currentPlainTextList
			currentPlainTextList = plainTextListCount
			plainTextListCount += 1
			defer
			{
				currentPlainTextList = enclosingList
			}
			var itemStyle = style
			itemStyle.listDepth += 1
			for (index, child) in children.enumerated()
			{
				guard let item = child as? ListItem
				else
				{
					continue
				}
				let marker: String
				switch item.checkbox
				{
				case .checked: marker = "☑ "
				case .unchecked: marker = "☐ "
				case nil:
					marker = startIndex.map
					{
						"\($0 + UInt(index)). "
					} ?? bulletMarker(depth: itemStyle.listDepth)
				}
				if item.childCount == 0
				{
					itemStyle.listContinuation = false
					beginParagraph(
						style: itemStyle,
						marker: marker
					)
				}
				for (blockIndex, block) in item.children.enumerated()
				{
					itemStyle.listContinuation = blockIndex > 0
					appendBlock(
						block,
						style: itemStyle,
						marker: blockIndex == 0 ? marker : ""
					)
				}
			}
			// Leave the final item separated from the following prose block.
			for index in paragraphStart ..< runs.count
				where runs[index].style.listDepth == itemStyle.listDepth
			{
				var finalStyle = runs[index].style
				finalStyle.listEnd = true
				runs[index] = MarkdownTextRun(
					text: runs[index].text,
					style: finalStyle
				)
			}

		}

		func bulletMarker(depth: Int) -> String
		{
			switch (depth - 1) % 3
			{
			case 1: "◦ "
			case 2: "▪ "
			default: "• "
			}
		}

		mutating func appendCodeBlock(
			_ block: CodeBlock,
			style: MarkdownTextStyle,
			marker: String
		)
		{
			if !marker.isEmpty
			{
				beginParagraph(
					style: style,
					marker: marker
				)
			}
			ensureParagraphBoundary()
			beginPlainTextBlock(list: nil)
			startParagraphSegment()
			var codeStyle = style
			codeStyle.codeBlock = true
			codeStyle.listContinuation = true
			codeStyle.codeBlockID = codeBlocks.count
			codeStyle.codeLanguage = block.language
			var headerStyle = codeStyle
			headerStyle.codeHeader = true
			append(
				"\n",
				style: headerStyle
			)
			startParagraphSegment()
			codeBlocks.append(block.code)
			if let diagram = diagram(in: block)
			{
				codeStyle.richBlock = diagram
				codeStyle.codeBlockEnd = true
				codeBlockRanges.append(NSRange(
					location: textLength,
					length: 1
				))
				append(
					"\u{FFFC}",
					style: codeStyle
				)
				return
			}
			codeBlockRanges.append(NSRange(
				location: textLength,
				length: block.code.utf16.count
			))
			appendCodeText(
				block.code,
				style: codeStyle
			)
			// Empty fences need a native line on which their copy control can be anchored.
			if block.code.isEmpty
			{
				codeStyle.codeBlockEnd = true
				append(
					"\n",
					style: codeStyle
				)
			}
		}

		func displayMath(in paragraph: Paragraph) -> MarkdownRichBlock?
		{
			guard let raw = sourceText(of: paragraph)
			else
			{
				return nil
			}
			let lines = raw.split(
				separator: "\n",
				omittingEmptySubsequences: false
			)
			guard lines.count >= 3
			else
			{
				return nil
			}
			let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
			let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines)
			let hasDollars = first == "$$" && last == "$$"
			let hasBrackets = first == "\\[" && last == "\\]"
			guard hasDollars || hasBrackets
			else
			{
				return nil
			}
			return MarkdownRichBlock(
				kind: .math,
				source: raw,
				payload: lines.dropFirst().dropLast().joined(separator: "\n")
			)
		}

		func diagram(in block: CodeBlock) -> MarkdownRichBlock?
		{
			guard block.language?.lowercased() == "mermaid", let raw = sourceText(of: block)
			else
			{
				return nil
			}
			let lines = raw.split(separator: "\n").map
			{
				$0.trimmingCharacters(in: .whitespacesAndNewlines)
			}
			guard let opening = lines.first, let closing = lines.last, lines.count >= 2,
					let marker = opening.first, marker == "`" || marker == "~"
			else
			{
				return nil
			}
			let count = opening.prefix
			{
				$0 == marker
			}.count
			guard count >= 3, closing.count >= count, closing.allSatisfy(
				{
					$0 == marker
				}
			)
			else
			{
				return nil
			}
			return MarkdownRichBlock(
				kind: .diagram,
				source: raw,
				payload: block.code
			)
		}

		func sourceText(of markup: any Markup) -> String?
		{
			guard let range = markup.range
			else
			{
				return nil
			}
			func offset(of location: SourceLocation) -> Int?
			{
				guard location.line > 0, location.line <= sourceLineOffsets.count,
						location.column > 0
				else
				{
					return nil
				}
				return sourceLineOffsets[location.line - 1] + location.column - 1
			}
			guard let start = offset(of: range.lowerBound), let end = offset(of: range.upperBound),
					start <= end, end <= sourceBytes.count
			else
			{
				return nil
			}
			return String(
				decoding: sourceBytes[start ..< end],
				as: UTF8.self
			)
		}

		mutating func appendCodeText(
			_ code: String,
			style: MarkdownTextStyle
		)
		{
			let text = code as NSString
			guard text.length > 0
			else
			{
				return
			}
			let lastParagraph = text.paragraphRange(for: NSRange(
				location: text.length - 1,
				length: 0
			))
			append(
				text.substring(to: lastParagraph.location),
				style: style
			)
			var finalStyle = style
			finalStyle.codeBlockEnd = true
			append(
				text.substring(from: lastParagraph.location),
				style: finalStyle
			)
		}

		mutating func appendTable(
			_ table: Table,
			style: MarkdownTextStyle
		)
		{
			ensureParagraphBoundary()
			beginPlainTextBlock(list: nil)
			let tableID = tableCount
			tableCount += 1
			let rows = [Array(table.head.children)] + table.body.children.map
			{
				Array($0.children)
			}
			for (rowIndex, row) in rows.enumerated()
			{
				for (column, cell) in row.enumerated()
				{
					guard let tableCell = cell as? Table.Cell,
							tableCell.colspan > 0, tableCell.rowspan > 0
					else
					{
						continue
					}
					startParagraphSegment()
					var cellStyle = style
					let alignment: MarkdownTableCell.Alignment
					switch table.columnAlignments[column]
					{
					case .center: alignment = .center
					case .right: alignment = .right
					default: alignment = .left
					}
					cellStyle.tableCell = MarkdownTableCell(
						tableID: tableID,
						row: rowIndex,
						column: column,
						columnCount: table.maxColumnCount,
						columnSpan: Int(tableCell.colspan),
						rowSpan: Int(tableCell.rowspan),
						alignment: alignment,
						header: rowIndex == 0
					)
					cellStyle.bold = rowIndex == 0
					appendInlines(
						cell.children,
						style: cellStyle
					)
					append(
						"\n",
						style: cellStyle
					)
				}
			}
		}

		mutating func appendInlines(
			_ children: MarkupChildren,
			style: MarkdownTextStyle
		)
		{
			for inline in children
			{
				var inlineStyle = style
				switch inline
				{
				case let text as Markdown.Text:
					appendTextWithMath(
						text.string,
						style: style
					)
				case is SoftBreak:
					if preserveSoftBreaks
					{
						appendHardBreak(style: style)
					}
					else
					{
						append(
							" ",
							style: style
						)
					}
				case is LineBreak: appendHardBreak(style: style)
				case let code as InlineCode:
					inlineStyle.code = true
					var paddingStyle = inlineStyle
					paddingStyle.codePadding = true
					append(
						"\u{00A0}",
						style: paddingStyle
					)
					append(
						code.code,
						style: inlineStyle
					)
					append(
						"\u{00A0}",
						style: paddingStyle
					)
				case is Strong:
					inlineStyle.bold = true
					appendInlines(
						inline.children,
						style: inlineStyle
					)
				case is Emphasis:
					inlineStyle.italic = true
					appendInlines(
						inline.children,
						style: inlineStyle
					)
				case is Strikethrough:
					inlineStyle.strikethrough = true
					appendInlines(
						inline.children,
						style: inlineStyle
					)
				case let link as Link:
					inlineStyle.link = link.destination
					if let destination = link.destination,
						destination.hasPrefix("/") || destination.hasPrefix("file://")
					{
						var iconStyle = inlineStyle
						iconStyle.fileLinkIcon = true
						append(
							"\u{FFFC}",
							style: iconStyle
						)
					}
					else if WebLinkDetector.webURL(link.destination) != nil
					{
						var iconStyle = inlineStyle
						iconStyle.webLinkIcon = true
						append(
							"\u{FFFC}",
							style: iconStyle
						)
					}
					appendInlines(
						link.children,
						style: inlineStyle
					)
				case let image as Image:
					if let path = localImagePath(image), let source = sourceText(of: image)
					{
						inlineStyle.richBlock = MarkdownRichBlock(
							kind: .imageGallery,
							source: source,
							payload: "",
							imagePaths: [path]
						)
						append(
							"\u{FFFC}",
							style: inlineStyle
						)
						continue
					}
					append(
						"[Image: ",
						style: style
					)
					appendInlines(
						image.children,
						style: style
					)
					append(
						"]",
						style: style
					)
					if let source = image.source
					{
						append(
							" (\(source))",
							style: style
						)
					}
				case let html as InlineHTML:
					append(
						html.rawHTML,
						style: style
					)
				default:
					appendInlines(
						inline.children,
						style: style
					)
				}
			}
		}

		mutating func appendTextWithMath(
			_ text: String,
			style: MarkdownTextStyle
		)
		{
			var start = text.startIndex
			var index = start
			while index < text.endIndex
			{
				guard let block = inlineMath[text[index]],
						text[index...].hasPrefix(block.placeholder)
				else
				{
					index = text.index(after: index)
					continue
				}
				appendTextWithWebLinks(
					String(text[start ..< index]),
					style: style
				)
				var mathStyle = style
				mathStyle.richBlock = block.math
				append(
					"\u{FFFC}",
					style: mathStyle
				)
				index = text.index(
					index,
					offsetBy: block.placeholder.count
				)
				start = index
			}
			appendTextWithWebLinks(
				String(text[start...]),
				style: style
			)
		}

		mutating func appendTextWithWebLinks(
			_ text: String,
			style: MarkdownTextStyle
		)
		{
			guard style.link == nil, !style.code
			else
			{
				append(
					text,
					style: style
				)
				return
			}
			let source = text as NSString
			let links = WebLinkDetector.links(in: text)
			var position = 0
			for link in links
			{
				guard let url = WebLinkDetector.webURL(link.destination)
				else
				{
					continue
				}
				if link.range.location > position
				{
					append(
						source.substring(with: NSRange(
							location: position,
							length: link.range.location - position
						)),
						style: style
					)
				}
				var linkStyle = style
				linkStyle.link = url.absoluteString
				var iconStyle = linkStyle
				iconStyle.webLinkIcon = true
				append(
					"\u{FFFC}",
					style: iconStyle
				)
				append(
					source.substring(with: link.range),
					style: linkStyle
				)
				position = NSMaxRange(link.range)
			}
			if position < source.length
			{
				append(
					source.substring(from: position),
					style: style
				)
			}
		}

		mutating func appendContainerMarker(
			_ marker: String,
			style: MarkdownTextStyle
		)
		{
			guard !marker.isEmpty
			else
			{
				return
			}
			beginParagraph(
				style: style,
				marker: marker
			)
		}

		mutating func beginParagraph(
			style: MarkdownTextStyle,
			marker: String
		)
		{
			ensureParagraphBoundary()
			let startsListItem = style.listDepth > 0 && !marker.isEmpty
			beginPlainTextBlock(list: startsListItem ? currentPlainTextList : nil)
			startParagraphSegment()
			append(
				marker,
				style: style
			)
		}

		mutating func ensureParagraphBoundary()
		{
			guard let last = runs.last, !last.text.hasSuffix("\n")
			else
			{
				return
			}
			append(
				"\n",
				style: last.style
			)
		}

		mutating func startParagraphSegment()
		{
			paragraphStart = runs.count
			paragraphContinuation = false
		}

		mutating func beginPlainTextBlock(list: Int?)
		{
			let continuesList = list != nil && list == previousPlainTextList
			plainTextBoundaries.append(MarkdownPlainTextBoundary(
				runIndex: runs.count,
				newlineCount: continuesList ? 1 : 2
			))
			previousPlainTextList = list
		}

		mutating func appendHardBreak(style: MarkdownTextStyle)
		{
			// LF preserves readable copied text; these segments share one visual paragraph.
			for index in paragraphStart ..< runs.count
			{
				var segmentStyle = runs[index].style
				segmentStyle.suppressParagraphSpacing = true
				runs[index] = MarkdownTextRun(
					text: runs[index].text,
					style: segmentStyle
				)
			}
			var breakStyle = style
			breakStyle.suppressParagraphSpacing = true
			append(
				"\n",
				style: breakStyle
			)
			paragraphStart = runs.count
			paragraphContinuation = true
		}

		mutating func append(
			_ text: String,
			style: MarkdownTextStyle
		)
		{
			guard !text.isEmpty
			else
			{
				return
			}
			var runStyle = style
			runStyle.paragraphContinuation = paragraphContinuation
			runs.append(MarkdownTextRun(
				text: text,
				style: runStyle
			))
			textLength += text.utf16.count
		}
	}
}
