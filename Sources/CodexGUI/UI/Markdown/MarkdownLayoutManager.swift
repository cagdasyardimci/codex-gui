import AppKit

/// Draws native Markdown surfaces without adding decorative characters to selectable prose.
/// TextKit callbacks are nonisolated. Markdown view creation, measurement and drawing
/// stay on MainActor.
@MainActor
final class MarkdownLayoutManager: NSLayoutManager
{
	static let quoteIndent = CGFloat(MarkdownMetrics.quoteIndent)
	static let codeInset = DesktopOutputCard.TextKitPresentation.transcriptCode.contentInset
	static let codeHeaderHeight = DesktopOutputCard.TextKitPresentation.transcriptCode.headerHeight
	static let codeBottomPadding = DesktopOutputCard.TextKitPresentation.transcriptCode
		.bottomPadding
	static let codeBlockSpacing = DesktopOutputCard.TextKitPresentation.transcriptCode.blockSpacing

	nonisolated override func drawBackground(
		forGlyphRange glyphsToShow: NSRange,
		at origin: NSPoint
	)
	{
		// The owning Markdown view uses TextKit on the main actor.
		precondition(Thread.isMainThread)
		let reference = MarkdownDrawingReference(manager: self)
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
			.markdownCodeBlockID,
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
			.markdownCodeBlockID,
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
		let filePreview = storage.attribute(
			.markdownFilePreview,
			at: range.location,
			effectiveRange: nil
		) as? Bool == true
		let left = max(
			0,
			(paragraph?.headIndent ?? Self.codeInset)
				- (filePreview ? 0 : Self.codeInset)
		)
		return NSRect(
			x: left,
			y: firstLine.minY,
			width: max(
				1,
				container.containerSize.width - left
			),
			height: lastContentLine.maxY - firstLine
				.minY + (filePreview ? DesktopOutputCard.TextKitPresentation.fileCode.bottomPadding
					: Self.codeBottomPadding)
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
			.markdownCodeBlockID,
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

			let filePreview = storage.attribute(
				.markdownFilePreview,
				at: range.location,
				effectiveRange: nil
			) as? Bool == true
			let language = storage.attribute(
				.markdownCodeLanguage,
				at: range.location,
				effectiveRange: nil
			) as? String
			DesktopOutputCard.drawTextKitCard(
				in: card,
				language: language,
				presentation: filePreview ? .fileCode :
					.transcriptCode
			)
		}
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
			.markdownCodeBlockID,
			at: lastCharacter,
			effectiveRange: nil
		) != nil
		// TextKit includes trailing paragraph spacing in the last line fragment.
		// Keep card footer padding inside the quote, and leave block spacing outside its rail.
		let externalSpacing = max(
			0,
			(paragraph?.paragraphSpacing ?? 0) - (endsWithCode ? Self.codeBottomPadding : 0)
		)
		let filePreview = storage.attribute(
			.markdownFilePreview,
			at: range.location,
			effectiveRange: nil
		) as? Bool == true
		let top = filePreview ? lineFragmentUsedRect(
			forGlyphAt: glyphs.location,
			effectiveRange: nil
		).minY : firstLine.minY
		return NSRect(
			x: CGFloat(railOffset) + (filePreview ? 0 : 2),
			y: top,
			width: filePreview ? 4 : 2,
			height: max(
				0,
				lastLine.maxY - externalSpacing - top
			)
		)
	}

	func quoteRailRanges(in storage: NSTextStorage) -> [Int: [NSRange]]
	{
		var quoteRanges: [Int: [NSRange]] = [:]
		storage.enumerateAttribute(
			.markdownQuoteRailOffsets,
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
			let filePreview = storage.attribute(
				.markdownFilePreview,
				at: range.location,
				effectiveRange: nil
			) as? Bool == true
			var segments = [range]
			if filePreview
			{
				segments = []
				let text = storage.string as NSString
				var start = range.location
				while start < NSMaxRange(range)
				{
					let paragraph = text.paragraphRange(for: NSRange(
						location: start,
						length: 0
					))
					segments.append(NSIntersectionRange(
						range,
						paragraph
					))
					start = NSMaxRange(paragraph)
				}
			}
			for offset in offsets
			{
				var ranges = quoteRanges[offset] ?? []
				for segment in segments
				{
					if let previous = ranges.last, NSMaxRange(previous) == segment.location,
						!filePreview || (storage.attribute(
						.paragraphStyle,
						at: segment.location,
						effectiveRange: nil
						) as? NSParagraphStyle)?.paragraphSpacingBefore == 0
					{
						ranges[ranges.count - 1] = NSUnionRange(
							previous,
							segment
						)
					}
					else
					{
						ranges.append(segment)
					}
				}
				quoteRanges[offset] = ranges
			}

		}
		return quoteRanges
	}

	private func drawQuotes(
		in storage: NSTextStorage,
		visibleCharacters: NSRange,
		container: NSTextContainer,
		origin: NSPoint
	)
	{
		let quoteRanges = quoteRailRanges(in: storage)
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
			.markdownThematicBreak,
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
			.markdownInlineCode,
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
private struct MarkdownDrawingReference: @unchecked Sendable
{
	let manager: MarkdownLayoutManager
}
