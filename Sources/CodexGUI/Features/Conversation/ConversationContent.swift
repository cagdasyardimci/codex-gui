import AppKit

/// Immutable text prepared for one displayed version of a conversation entry.
final class PreparedConversationContent: @unchecked Sendable
{
	let attributedString: NSAttributedString
	let codeBlocks: [String]
	let codeBlockRanges: [NSRange]
	private struct SizeKey: Hashable
	{
		let width: CGFloat
		let expandable: Bool
		let presentation: Int
	}
	@MainActor private var measuredSizes: [SizeKey: NSSize] = [:]
	@MainActor private var measuredOrder: [SizeKey] = []
	@MainActor private var displayTexts: [Int: NSAttributedString] = [:]
	@MainActor private var naturalWidths: [Int: CGFloat] = [:]
	@MainActor private var bodyHeights: [SizeKey: CGFloat] = [:]
	@MainActor private var bodyHeightOrder: [SizeKey] = []

	@MainActor
	init(_ parsed: ParsedConversationContent)
	{
		let result = NSMutableAttributedString(string: "")
		for run in parsed.runs
		{
			var attributes: [NSAttributedString.Key: Any] = [
				.font: Self.font(for: run.style),
				.foregroundColor: run.style.link == nil ? NSColor.labelColor : NSColor.linkColor,
			]
			let paragraph = NSMutableParagraphStyle()
			paragraph.lineBreakMode =
				run.style.code || run.style.monospaced
					? .byCharWrapping : .byWordWrapping
			paragraph.lineSpacing = run.style.code || run.style.monospaced ? 2 : 4
			attributes[.paragraphStyle] = paragraph
			if run.style.code
			{
				attributes[.backgroundColor] = NSColor.controlBackgroundColor
				paragraph.tailIndent = -96
			}
			if let link = run.style.link, let url = URL(string: link)
			{
				attributes[.link] = url
				attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
			}
			result.append(NSAttributedString(
				string: run.text,
				attributes: attributes
			))
		}
		attributedString = NSAttributedString(attributedString: result)
		codeBlocks = parsed.codeBlocks
		codeBlockRanges = parsed.codeBlockRanges
	}

	@MainActor
	func cachedSize(
		width: CGFloat,
		expandable: Bool,
		presentation: Int = 0,
		calculate: () -> NSSize
	) -> NSSize
	{
		let key = SizeKey(
			width: width,
			expandable: expandable,
			presentation: presentation
		)
		if let size = measuredSizes[key]
		{
			return size
		}
		let size = calculate()
		measuredSizes[key] = size
		measuredOrder.append(key)
		if measuredOrder.count > 32
		{
			measuredSizes.removeValue(forKey: measuredOrder.removeFirst())
		}
		return size
	}

	@MainActor
	func cachedDisplayText(
		presentation: Int,
		calculate: () -> NSAttributedString
	)
		-> NSAttributedString
	{
		if let text = displayTexts[presentation]
		{
			return text
		}
		let text = NSAttributedString(attributedString: calculate())
		if displayTexts.count < 5
		{
			displayTexts[presentation] = text
		}
		return text
	}

	@MainActor
	func cachedNaturalWidth(
		presentation: Int,
		calculate: () -> CGFloat
	) -> CGFloat
	{
		if let width = naturalWidths[presentation]
		{
			return width
		}
		let width = calculate()
		if naturalWidths.count < 5
		{
			naturalWidths[presentation] = width
		}
		return width
	}

	@MainActor
	func cachedBodyHeight(
		width: CGFloat,
		presentation: Int,
		calculate: () -> CGFloat
	) -> CGFloat
	{
		let key = SizeKey(
			width: width,
			expandable: false,
			presentation: presentation
		)
		if let height = bodyHeights[key]
		{
			return height
		}
		let height = calculate()
		bodyHeights[key] = height
		bodyHeightOrder.append(key)
		if bodyHeightOrder.count > 32
		{
			bodyHeights.removeValue(forKey: bodyHeightOrder.removeFirst())
		}
		return height
	}

	@MainActor
	private static func font(for style: ConversationTextStyle) -> NSFont
	{
		if style.code || style.monospaced
		{
			return .monospacedSystemFont(
				ofSize: style.code ? 12 : 13,
				weight: .regular
			)
		}
		let size: CGFloat
		switch style.heading
		{
		case 1: size = 18
		case 2: size = 16
		case 3: size = 14
		default: size = 15
		}
		if style.bold || style.heading > 0
		{
			return .boldSystemFont(ofSize: size)
		}
		if style.italic
		{
			return NSFontManager.shared.convert(
				.systemFont(ofSize: size),
				toHaveTrait: .italicFontMask
			)
		}
		return .systemFont(ofSize: size)
	}
}

actor ConversationContentCache
{
	private struct Key: Hashable
	{
		let body: String
		let markdown: Bool
	}

	private var values: [Key: PreparedConversationContent] = [:]
	private var insertionOrder: [Key] = []
	private var storedBytes = 0
	private let capacity = 64
	private let byteCapacity = 6 * 1024 * 1024

	func content(
		body: String,
		markdown: Bool
	) async -> PreparedConversationContent
	{
		let key = Key(
			body: body,
			markdown: markdown
		)
		if let cached = values[key]
		{
			return cached
		}

		let parsed = ConversationContentParser.parse(
			body,
			markdown: markdown
		)
		let prepared = await PreparedConversationContent(parsed)
		let byteCount = body.utf8.count
		if values[key] == nil && byteCount <= byteCapacity
		{
			values[key] = prepared
			insertionOrder.append(key)
			storedBytes += byteCount
			while insertionOrder.count > capacity || storedBytes > byteCapacity
			{
				let oldest = insertionOrder.removeFirst()
				storedBytes -= oldest.body.utf8.count
				values.removeValue(forKey: oldest)
			}
		}
		return prepared
	}
}

struct ParsedConversationContent: Sendable
{
	let runs: [ConversationTextRun]
	let codeBlocks: [String]
	let codeBlockRanges: [NSRange]
}

struct ConversationTextRun: Sendable
{
	let text: String
	let style: ConversationTextStyle
}

struct ConversationTextStyle: Sendable
{
	var heading = 0
	var bold = false
	var italic = false
	var code = false
	var monospaced = false
	var link: String?
}

enum ConversationContentParser
{
	static func parse(
		_ body: String,
		markdown: Bool
	) -> ParsedConversationContent
	{
		guard markdown
		else
		{
			return ParsedConversationContent(
				runs: [ConversationTextRun(
					text: body,
					style: ConversationTextStyle(monospaced: true)
				)],
				codeBlocks: [],
				codeBlockRanges: []
			)
		}

		var runs: [ConversationTextRun] = []
		var codeBlocks: [String] = []
		var codeBlockRanges: [NSRange] = []
		var textLength = 0
		let lines = body.split(
			separator: "\n",
			omittingEmptySubsequences: false
		)
		var index = 0
		while index < lines.count
		{
			let line = String(lines[index])
			if let fence = openingFence(line)
			{
				index += 1
				var code = ""
				while index < lines.count && !isClosingFence(
					String(lines[index]),
					matching: fence
				)
				{
					code += String(lines[index])
					if index < lines.count - 1
					{
						code += "\n"
					}
					index += 1
				}
				codeBlocks.append(code)
				codeBlockRanges.append(NSRange(
					location: textLength,
					length: (code as NSString).length
				))
				runs.append(ConversationTextRun(
					text: code,
					style: ConversationTextStyle(code: true)
				))
				textLength += (code as NSString).length
				if index < lines.count
				{
					index += 1
				}
				if index < lines.count
				{
					runs.append(ConversationTextRun(
						text: "\n",
						style: ConversationTextStyle()
					))
					textLength += 1
				}
				continue
			}

			let (inline, style) = parseTextLine(line)
			runs.append(contentsOf: inline)
			textLength += inline.reduce(0)
			{
				$0 + ($1.text as NSString).length
			}
			if index < lines.count - 1
			{
				runs.append(ConversationTextRun(
					text: "\n",
					style: style
				))
				textLength += 1
			}
			index += 1
		}
		return ParsedConversationContent(
			runs: runs,
			codeBlocks: codeBlocks,
			codeBlockRanges: codeBlockRanges
		)
	}

	private static func parseTextLine(_ line: String)
		-> (runs: [ConversationTextRun], style: ConversationTextStyle)
	{
		var style = ConversationTextStyle()
		var display = line
		let indentationWidth = line.prefix(while:
			{
				$0 == " "
			}).count
		let trimmed = String(line.dropFirst(indentationWidth))
		let headingLevel = trimmed.prefix(while:
			{
				$0 == "#"
			}).count
		if (1 ... 6).contains(headingLevel), trimmed.dropFirst(headingLevel).hasPrefix(" ")
		{
			style.heading = headingLevel
			display = String(trimmed.dropFirst(headingLevel + 1))
		}
		else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
		{
			display = String(
				repeating: " ",
				count: indentationWidth
			) + "• " +
				String(trimmed.dropFirst(2))
		}
		else if let marker = numberedListMarker(in: trimmed)
		{
			display = String(
				repeating: " ",
				count: indentationWidth
			) + marker.prefix + marker.body
		}
		let inline = inlineRuns(
			in: display,
			style: style
		)
		return (inline, style)
	}

	private static func openingFence(_ line: String) -> (marker: Character, count: Int)?
	{
		let trimmed = line.drop(while:
			{
				$0 == " "
			})
		guard let marker = trimmed.first, marker == "`" || marker == "~"
		else
		{
			return nil
		}
		let count = trimmed.prefix(while:
			{
				$0 == marker
			}).count
		return count >= 3 ? (marker, count) : nil
	}

	private static func isClosingFence(
		_ line: String,
		matching fence: (marker: Character, count: Int)
	) -> Bool
	{
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		return trimmed.count >= fence.count && trimmed.allSatisfy
		{
			$0 == fence.marker
		}
	}

	private static func numberedListMarker(in line: String) -> (prefix: String, body: String)?
	{
		let digits = line.prefix(while:
			{
				$0.isNumber
			})
		guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ")
		else
		{
			return nil
		}
		return ("\(digits). ", String(line.dropFirst(digits.count + 2)))
	}

	private static func inlineRuns(
		in text: String,
		style: ConversationTextStyle
	)
		-> [ConversationTextRun]
	{
		guard text.contains(where:
			{
				"*_`[~".contains($0)
			})
		else
		{
			return [ConversationTextRun(
				text: text,
				style: style
			)]
		}
		let options = AttributedString.MarkdownParsingOptions(
			interpretedSyntax: .inlineOnlyPreservingWhitespace
		)
		guard let attributed = try? AttributedString(
			markdown: text,
			options: options
		)
		else
		{
			return [ConversationTextRun(
				text: text,
				style: style
			)]
		}
		return attributed.runs.map
		{
			run in
			var runStyle = style
			let intent = run.inlinePresentationIntent ?? []
			runStyle.bold = runStyle.bold || intent.contains(.stronglyEmphasized)
			runStyle.italic = runStyle.italic || intent.contains(.emphasized)
			runStyle.code = runStyle.code || intent.contains(.code)
			runStyle.link = run.link?.absoluteString
			return ConversationTextRun(
				text: String(attributed[run.range].characters),
				style: runStyle
			)
		}
	}
}
