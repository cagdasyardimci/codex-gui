import AppKit

extension NSAttributedString.Key
{
	static let conversationSourceText = NSAttributedString.Key("conversationSourceText")
	static let conversationInlineCodeSource = NSAttributedString.Key("conversationInlineCodeSource")
	static let conversationInlineCode = NSAttributedString.Key("conversationInlineCode")
	static let conversationCodeBlockID = NSAttributedString.Key("conversationCodeBlockID")
	static let conversationCodeHeader = NSAttributedString.Key("conversationCodeHeader")
	static let conversationCodeLanguage = NSAttributedString.Key("conversationCodeLanguage")
	static let conversationQuoteDepth = NSAttributedString.Key("conversationQuoteDepth")
	static let conversationQuoteRailOffsets = NSAttributedString.Key("conversationQuoteRailOffsets")
	static let conversationThematicBreak = NSAttributedString.Key("conversationThematicBreak")
}

/// Draws native Markdown surfaces without adding decorative characters to selectable prose.
/// TextKit callbacks are nonisolated. Transcript creation, measurement and drawing
/// stay on MainActor.
@MainActor
final class ConversationMarkdownLayoutManager: NSLayoutManager
{
	static let quoteIndent = CGFloat(ConversationMarkdownMetrics.quoteIndent)
	static let codeInset: CGFloat = 18
	static let codeHeaderHeight: CGFloat = 44
	static let codeBottomPadding: CGFloat = 16
	static let codeBlockSpacing: CGFloat = 16

	nonisolated override func drawBackground(
		forGlyphRange glyphsToShow: NSRange,
		at origin: NSPoint
	)
	{
		// The transcript creates, measures and displays its TextKit layout on the main actor.
		precondition(Thread.isMainThread)
		let reference = ConversationMarkdownDrawingReference(manager: self)
		MainActor.assumeIsolated
		{
			[reference] in
			reference.manager.drawMarkdownBackgrounds(
				forGlyphRange: glyphsToShow,
				at: origin
			)
		}
	}

	private func drawMarkdownBackgrounds(
		forGlyphRange glyphsToShow: NSRange,
		at origin: NSPoint
	)
	{
		guard let storage = textStorage, storage.length > 0,
				glyphsToShow.length > 0,
				let container = textContainer(
				forGlyphAt: glyphsToShow.location,
				effectiveRange: nil
				)
		else
		{
			super.drawBackground(
				forGlyphRange: glyphsToShow,
				at: origin
			)
			return
		}
		let visibleCharacters = characterRange(
			forGlyphRange: glyphsToShow,
			actualGlyphRange: nil
		)
		drawCodeBlocks(
			in: storage,
			visibleCharacters: visibleCharacters,
			container: container,
			origin: origin
		)
		drawQuotes(
			in: storage,
			visibleCharacters: visibleCharacters,
			container: container,
			origin: origin
		)
		drawThematicRules(
			in: storage,
			visibleCharacters: visibleCharacters,
			container: container,
			origin: origin
		)
		drawInlineCode(
			in: storage,
			visibleCharacters: visibleCharacters,
			container: container,
			origin: origin
		)
		// Native selection highlights remain above the decorative backgrounds.
		super.drawBackground(
			forGlyphRange: glyphsToShow,
			at: origin
		)
	}

	func codeBlockHeaderRect(
		atCharacter location: Int,
		in container: NSTextContainer
	) -> NSRect?
	{
		guard let storage = textStorage, location < storage.length, location >= 0
		else
		{
			return nil
		}
		var range = NSRange()
		guard storage.attribute(
			.conversationCodeBlockID,
			at: location,
			longestEffectiveRange: &range,
			in: NSRange(
				location: 0,
				length: storage.length
			)
		) != nil
		else
		{
			return nil
		}
		ensureLayout(for: container)
		let glyph = glyphIndexForCharacter(at: range.location)
		return lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		)
	}

	func codeBlockRect(
		atCharacter location: Int,
		in container: NSTextContainer
	) -> NSRect?
	{
		guard let storage = textStorage, location >= 0, location < storage.length
		else
		{
			return nil
		}
		var range = NSRange()
		guard storage.attribute(
			.conversationCodeBlockID,
			at: location,
			longestEffectiveRange: &range,
			in: NSRange(
				location: 0,
				length: storage.length
			)
		) != nil
		else
		{
			return nil
		}
		ensureLayout(for: container)
		let glyphs = glyphRange(
			forCharacterRange: range,
			actualCharacterRange: nil
		)
		guard glyphs.length > 0
		else
		{
			return nil
		}
		let firstLine = lineFragmentRect(
			forGlyphAt: glyphs.location,
			effectiveRange: nil
		)
		let lastContentLine = lineFragmentUsedRect(
			forGlyphAt: NSMaxRange(glyphs) - 1,
			effectiveRange: nil
		)
		let paragraph = storage.attribute(
			.paragraphStyle,
			at: range.location,
			effectiveRange: nil
		) as? NSParagraphStyle
		let left = max(
			0,
			(paragraph?.headIndent ?? Self.codeInset) - Self.codeInset
		)
		return NSRect(
			x: left,
			y: firstLine.minY,
			width: max(
				1,
				container.containerSize.width - left
			),
			height: lastContentLine.maxY - firstLine.minY + Self.codeBottomPadding
		)
	}

	private func drawCodeBlocks(
		in storage: NSTextStorage,
		visibleCharacters: NSRange,
		container: NSTextContainer,
		origin: NSPoint
	)
	{
		storage.enumerateAttribute(
			.conversationCodeBlockID,
			in: NSRange(
				location: 0,
				length: storage.length
			),
			options: []
		)
		{
			value, range, _ in
			guard value != nil, NSIntersectionRange(
				range,
				visibleCharacters
			).length > 0
			else
			{
				return
			}
			guard let blockRect = self.codeBlockRect(
				atCharacter: range.location,
				in: container
			)
			else
			{
				return
			}
			let card = blockRect.offsetBy(
				dx: origin.x,
				dy: origin.y
			)

			let path = NSBezierPath(
				roundedRect: card,
				xRadius: 16,
				yRadius: 16
			)
			AppKitColorTokens.elevated.setFill()
			path.fill()
			AppKitColorTokens.border.setStroke()
			path.lineWidth = 1
			path.stroke()
			if let language = storage.attribute(
				.conversationCodeLanguage,
				at: range.location,
				effectiveRange: nil
			) as? String, !language.isEmpty
			{
				let headerAttributes: [NSAttributedString.Key: Any] = [
					.font: NSFont.systemFont(
						ofSize: 12,
						weight: .medium
					),
					.foregroundColor: NSColor.labelColor,
				]
				("‹/›" as NSString).draw(
					at: NSPoint(
						x: card.minX + Self.codeInset,
						y: card.minY + 14
					),
					withAttributes: headerAttributes
				)
				let label = NSRect(
					x: card.minX + Self.codeInset + 26,
					y: card.minY + 14,
					width: max(
						1,
						card.width - Self.codeInset - 70
					),
					height: 16
				)
				(Self.codeLanguageTitle(language) as NSString).draw(
					in: label,
					withAttributes: headerAttributes
				)
			}
		}
	}

	private static func codeLanguageTitle(_ language: String) -> String
	{
		let titles = [
			"python": "Python",
			"swift": "Swift",
			"javascript": "JavaScript",
			"typescript": "TypeScript",
			"json": "JSON",
			"html": "HTML",
			"css": "CSS",
			"bash": "Bash",
			"mermaid": "Mermaid",
			"text": "Text",
		]
		return titles[language.lowercased()] ?? language
	}

	func quoteRailRect(
		forCharacterRange range: NSRange,
		railOffset: Int = 0,
		in container: NSTextContainer
	) -> NSRect?
	{
		guard let storage = textStorage, range.length > 0,
				range.location >= 0, NSMaxRange(range) <= storage.length
		else
		{
			return nil
		}
		ensureLayout(for: container)
		let glyphs = glyphRange(
			forCharacterRange: range,
			actualCharacterRange: nil
		)
		guard glyphs.length > 0
		else
		{
			return nil
		}
		let firstLine = lineFragmentRect(
			forGlyphAt: glyphs.location,
			effectiveRange: nil
		)
		let lastLine = lineFragmentRect(
			forGlyphAt: NSMaxRange(glyphs) - 1,
			effectiveRange: nil
		)
		let lastCharacter = NSMaxRange(range) - 1
		let paragraph = storage.attribute(
			.paragraphStyle,
			at: lastCharacter,
			effectiveRange: nil
		) as? NSParagraphStyle
		let endsWithCode = storage.attribute(
			.conversationCodeBlockID,
			at: lastCharacter,
			effectiveRange: nil
		) != nil
		// TextKit includes trailing paragraph spacing in the last line fragment.
		// Keep card footer padding inside the quote, and leave block spacing outside its rail.
		let externalSpacing = max(
			0,
			(paragraph?.paragraphSpacing ?? 0) - (endsWithCode ? Self.codeBottomPadding : 0)
		)
		return NSRect(
			x: CGFloat(railOffset) + 2,
			y: firstLine.minY,
			width: 2,
			height: max(
				0,
				lastLine.maxY - externalSpacing - firstLine.minY
			)
		)
	}

	private func drawQuotes(
		in storage: NSTextStorage,
		visibleCharacters: NSRange,
		container: NSTextContainer,
		origin: NSPoint
	)
	{
		var quoteRanges: [Int: [NSRange]] = [:]
		storage.enumerateAttribute(
			.conversationQuoteRailOffsets,
			in: NSRange(
				location: 0,
				length: storage.length
			),
			options: []
		)
		{
			value, range, _ in
			guard let offsets = value as? [Int], !offsets.isEmpty
			else
			{
				return
			}
			for offset in offsets
			{
				var ranges = quoteRanges[offset] ?? []
				if let previous = ranges.last, NSMaxRange(previous) == range.location
				{
					ranges[ranges.count - 1] = NSUnionRange(
						previous,
						range
					)
				}
				else
				{
					ranges.append(range)
				}
				quoteRanges[offset] = ranges
			}

		}
		NSColor.separatorColor.setFill()
		for (offset, ranges) in quoteRanges
		{
			for range in ranges
			{
				guard NSIntersectionRange(
					range,
					visibleCharacters
				).length > 0
				else
				{
					continue
				}
				guard let rail = quoteRailRect(
					forCharacterRange: range,
					railOffset: offset,
					in: container
				)
				else
				{
					continue
				}
				rail.offsetBy(
					dx: origin.x,
					dy: origin.y
				).fill()
			}
		}
	}

	private func drawThematicRules(
		in storage: NSTextStorage,
		visibleCharacters: NSRange,
		container: NSTextContainer,
		origin: NSPoint
	)
	{
		storage.enumerateAttribute(
			.conversationThematicBreak,
			in: visibleCharacters,
			options: []
		)
		{
			value, range, _ in
			guard value as? Bool == true
			else
			{
				return
			}
			let glyph = self.glyphIndexForCharacter(at: range.location)
			let line = self.lineFragmentRect(
				forGlyphAt: glyph,
				effectiveRange: nil
			)
			NSColor.separatorColor.setFill()
			NSRect(
				x: origin.x + line.minX,
				y: origin.y + line.midY,
				width: line.width,
				height: 1
			).fill()
		}
	}

	private func drawInlineCode(
		in storage: NSTextStorage,
		visibleCharacters: NSRange,
		container: NSTextContainer,
		origin: NSPoint
	)
	{
		storage.enumerateAttribute(
			.conversationInlineCode,
			in: visibleCharacters,
			options: []
		)
		{
			value, range, _ in
			guard value as? Bool == true
			else
			{
				return
			}
			let glyphs = self.glyphRange(
				forCharacterRange: range,
				actualCharacterRange: nil
			)
			self.enumerateEnclosingRects(
				forGlyphRange: glyphs,
				withinSelectedGlyphRange: NSRange(
					location: NSNotFound,
					length: 0
				),
				in: container
			)
			{
				rect, _ in
				let font = storage.attribute(
					.font,
					at: range.location,
					effectiveRange: nil
				) as? NSFont
				let height = min(
					rect.height,
					(font?.pointSize ?? 13) + 4
				)
				let background = NSRect(
					x: origin.x + rect.minX,
					y: origin.y + rect.midY - height / 2,
					width: rect.width,
					height: height
				)
				NSColor.labelColor.withAlphaComponent(0.09).setFill()
				NSBezierPath(
					roundedRect: background,
					xRadius: 6,
					yRadius: 6
				).fill()
			}
		}
	}
}

/// Bridges the SDK callback's task-isolated receiver to the verified main-thread drawing scope.
private struct ConversationMarkdownDrawingReference: @unchecked Sendable
{
	let manager: ConversationMarkdownLayoutManager
}
