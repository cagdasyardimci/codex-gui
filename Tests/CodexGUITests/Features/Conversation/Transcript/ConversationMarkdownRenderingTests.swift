import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationMarkdownRenderingTests
{
	@Test func combinedEmphasisAndStrikethroughHaveNativeAttributes() async throws
	{
		let content = await prepare("***both*** ~~deleted~~ [link](https://example.com)")
		let text = content.attributedString
		let emphasis = try font(
			in: text,
			at: "both"
		)
		let traits = NSFontManager.shared.traits(of: emphasis)
		#expect(traits.contains(.boldFontMask))
		#expect(traits.contains(.italicFontMask))
		#expect(attribute(
			.strikethroughStyle,
			in: text,
			at: "deleted"
		) as? Int == NSUnderlineStyle.single.rawValue)
		#expect((attribute(
			.link,
			in: text,
			at: "link"
		) as? URL)?.absoluteString == "https://example.com")
	}

	@Test func inlineCodeDoesNotIndentItsParagraphOrCreateCopyControls() async throws
	{
		_ = NSApplication.shared
		let body = "ordinary `literal *code*` ending"
		let content = await prepare(body)
		let item = makeItem(
			body: body,
			content: content
		)
		let textView = try #require(findTextView(in: item.view))
		let ordinary = try paragraph(
			in: content.attributedString,
			at: "ordinary"
		)
		let inline = try paragraph(
			in: content.attributedString,
			at: "literal *code*"
		)
		#expect(inline.tailIndent == 0)
		#expect(inline.headIndent == ordinary.headIndent)
		#expect(inline.lineBreakMode == ordinary.lineBreakMode)
		#expect(content.codeBlocks.isEmpty)
		#expect(allButtons(in: item.view).allSatisfy
		{
			!($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
		})
		#expect(textView.isSelectable)
		#expect(!textView.isEditable)
	}

	@Test func headingsAndNestedListsHaveNativeFontAndHangingIndent() async throws
	{
		let content = await prepare("# Heading\n\n- parent\n  - child\n    - grandchild")
		let headingFont = try font(
			in: content.attributedString,
			at: "Heading"
		)
		#expect(headingFont.pointSize == 24)
		#expect(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
		let paragraphs = try ["parent", "child", "grandchild"].map
		{
			try paragraph(
				in: content.attributedString,
				at: $0
			)
		}
		#expect(paragraphs.allSatisfy
		{
			$0.headIndent > $0.firstLineHeadIndent
		})
		#expect(paragraphs[1].headIndent > paragraphs[0].headIndent)
		#expect(paragraphs[2].headIndent > paragraphs[1].headIndent)
	}

	@Test func tableCellsUseOneNativeTableWithDeclaredAlignments() async throws
	{
		let content = await prepare("""
		| Left | Center | Right |
		| :--- | :---: | ---: |
		| alpha | beta | gamma |

		After table.
		""")
		var table: NSTextTable?
		for (label, alignment) in [
			("Left", NSTextAlignment.left),
			("Center", .center),
			("Right", .right),
			("alpha", .left),
			("beta", .center),
			("gamma", .right),
		]
		{
			let style = try paragraph(
				in: content.attributedString,
				at: label
			)
			#expect(style.alignment == alignment)
			#expect(style.lineBreakMode == .byWordWrapping)
			try #require(style.textBlocks.count == 1)
			let cell = try #require(style.textBlocks.first as? NSTextTableBlock)
			#expect(cell.table.numberOfColumns == 3)
			if let table
			{
				#expect(cell.table === table)
			}
			else
			{
				table = cell.table
			}
		}
		#expect(NSFontManager.shared.traits(of: try font(
			in: content.attributedString,
			at: "Left"
		)).contains(.boldFontMask))
		#expect(!NSFontManager.shared.traits(of: try font(
			in: content.attributedString,
			at: "alpha"
		)).contains(.boldFontMask))
		#expect(!content.attributedString.string.contains("|"))
		#expect(try paragraph(
			in: content.attributedString,
			at: "After table."
		).textBlocks.isEmpty)
		#expect(content.attributedString.string.hasSuffix("gamma\nAfter table."))
	}

	@Test func quoteRailsFollowTheirContainerWhileOuterRailsRemainContinuous() async throws
	{
		let content = await prepare("- item\n\n  > quote inside list\n\n"
			+ "> outer paragraph\n>\n> - quoted list item\n>\n>   > nested quote")
		let text = content.attributedString
		#expect(attribute(
			.conversationQuoteRailOffsets,
			in: text,
			at: "quote inside list"
		) as? [Int] == [22])
		#expect(attribute(
			.conversationQuoteRailOffsets,
			in: text,
			at: "outer paragraph"
		) as? [Int] == [0])
		#expect(attribute(
			.conversationQuoteRailOffsets,
			in: text,
			at: "quoted list item"
		) as? [Int] == [0])
		#expect(attribute(
			.conversationQuoteRailOffsets,
			in: text,
			at: "nested quote"
		) as? [Int] == [0, 38])
		#expect(try paragraph(
			in: text,
			at: "quote inside list"
		).headIndent > 22)
		#expect(!text.string.contains("│"))
	}

	@Test func tableWordsStayTogetherWhileLongTokensRemainReachableAtBothWidths() async throws
	{
		let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
		let token = String(
			repeating: "LongUnbrokenToken",
			count: 12
		)
		let body = "| Prose | Token |\n| --- | --- |\n| " + words.joined(separator: " ")
			+ " | " + token + " |\n\nAfter table."
		let content = await prepare(body)
		let text = content.attributedString.string as NSString
		for width: CGFloat in [240, 440]
		{
			let native = makeNativeLayout(
				content.attributedString,
				width: width
			)
			for word in words
			{
				let range = text.range(of: word)
				let first = lineRect(
					at: range.location,
					layout: native.manager
				)
				let last = lineRect(
					at: NSMaxRange(range) - 1,
					layout: native.manager
				)
				#expect(first.minY == last.minY)
			}
			let tokenRange = text.range(of: token)
			let firstTokenLine = lineRect(
				at: tokenRange.location,
				layout: native.manager
			)
			let lastTokenLine = lineRect(
				at: NSMaxRange(tokenRange) - 1,
				layout: native.manager
			)
			#expect(lastTokenLine.minY > firstTokenLine.minY)
			let laidOut = native.manager.characterRange(
				forGlyphRange: native.manager.glyphRange(for: native.container),
				actualGlyphRange: nil
			)
			#expect(laidOut == NSRange(
				location: 0,
				length: native.storage.length
			))
			let used = native.manager.usedRect(for: native.container)
			#expect(used.maxX <= width + 0.5)
			let after = lineRect(
				at: text.range(of: "After table.").location,
				layout: native.manager
			)
			#expect(after.minY >= lastTokenLine.maxY)
		}
	}

	@Test func canonicalTableKeepsShortValuesReadableAtTheNarrowestBubbleWidth() async throws
	{
		_ = NSApplication.shared
		let source = ConversationMarkdownTestFixture.paritySource
		let start = try #require(source.range(of: "| Left aligned |"))
		let end = try #require(source.range(of: "## 6. Code blocks and copying"))
		let content = await prepare(String(source[start.lowerBound ..< end.lowerBound]))
		let native = makeNativeLayout(
			content.attributedString,
			width: 216
		)
		let textView = NSTextView(
			frame: NSRect(
				x: 0,
				y: 0,
				width: 216,
				height: 10_000
			),
			textContainer: native.container
		)
		textView.textContainerInset = .zero
		native.container.widthTracksTextView = false
		native.container.heightTracksTextView = false
		let text = native.storage.string as NSString
		for width: CGFloat in [216, 640, 216]
		{
			textView.setFrameSize(NSSize(
				width: width,
				height: 10_000
			))
			native.container.size = NSSize(
				width: width,
				height: 10_000
			)
			native.manager.ensureLayout(for: native.container)
			for value in ["12.50", "1234", "longer", "naturally", "several"]
			{
				let range = text.range(of: value)
				try #require(range.location != NSNotFound)
				#expect(lineRect(
					at: range.location,
					layout: native.manager
				).minY == lineRect(
					at: NSMaxRange(range) - 1,
					layout: native.manager
				).minY)
			}
			for value in ["Center", "table_code"]
			{
				let range = text.range(of: value)
				var lines: Set<CGFloat> = []
				for location in range.location ..< NSMaxRange(range)
				{
					lines.insert(lineRect(
						at: location,
						layout: native.manager
					).minY)
				}
				#expect(lines.count <= 2)
			}
			let marker = text.range(of: "TABLE_END_MARKER")
			try #require(marker.location != NSNotFound)
			#expect(lineRect(
				at: marker.location,
				layout: native.manager
			).minY >= lineRect(
				at: text.range(of: "-42").location,
				layout: native.manager
			).maxY)
			#expect(native.manager.usedRect(for: native.container).maxX <= width + 0.5)
			#expect(native.manager.characterRange(
				forGlyphRange: native.manager.glyphRange(for: native.container),
				actualGlyphRange: nil
			) == NSRange(
				location: 0,
				length: native.storage.length
			))
			let cell = try #require(paragraph(
				in: native.storage,
				at: "12.50"
			).textBlocks.first as? NSTextTableBlock)
			#expect(cell.width(
				for: .border,
				edge: .maxY
			) > 0)
		}
		#expect(text.contains("Center bold") && text.contains("obsolete"))
		#expect(text.contains("Escaped pipe: A | B"))
		#expect(text.hasSuffix("below the table."))
	}

	@Test func codeBlocksHaveTightInternalLinesAndAGapBeforeFollowingBlocks() async throws
	{
		let body = "# Before\n\n```text\nfirst\nsecond\n```\n\n## After\n\n"
			+ "```text\nthird\n```\n\n```text\nfourth\n```"
		let content = await prepare(body)
		let text = content.attributedString
		#expect(content.codeBlocks == ["first\nsecond\n", "third\n", "fourth\n"])
		#expect(content.codeBlockRanges.count == 3)
		for (range, code) in zip(
			content.codeBlockRanges,
			content.codeBlocks
		)
		{
			#expect((text.string as NSString).substring(with: range) == code)
			#expect(range.length == code.utf16.count)
		}
		#expect(try paragraph(
			in: text,
			at: "first"
		).paragraphSpacing == 0)
		for lastLine in ["second", "third", "fourth"]
		{
			#expect(try paragraph(
				in: text,
				at: lastLine
			).paragraphSpacing == 32)
		}
		let native = makeNativeLayout(
			text,
			width: 320
		)
		let display = text.string as NSString
		let first = lineRect(
			at: display.range(of: "first").location,
			layout: native.manager
		)
		let second = lineRect(
			at: display.range(of: "second").location,
			layout: native.manager
		)
		let heading = lineRect(
			at: display.range(of: "After").location,
			layout: native.manager
		)
		let third = lineRect(
			at: display.range(of: "third").location,
			layout: native.manager
		)
		let fourth = lineRect(
			at: display.range(of: "fourth").location,
			layout: native.manager
		)
		let internalAdvance = second.minY - first.minY
		#expect(internalAdvance > 0)
		#expect(fourth.minY - third.minY >= internalAdvance + 7.5)
		#expect(heading.minY - second.minY >= internalAdvance + 7.5)
	}

	@Test func preparedSystemColorsResolveInLightAndDarkAppearances() throws
	{
		let parsed = ConversationContentParser.parse(
			"body [link](https://example.com)\n\n```text\ncode\n```",
			markdown: true
		)
		for name in [NSAppearance.Name.aqua, .darkAqua]
		{
			let appearance = try #require(NSAppearance(named: name))
			var content: PreparedConversationContent?
			appearance.performAsCurrentDrawingAppearance
			{
				content = PreparedConversationContent(parsed)
			}
			let text = try #require(content).attributedString
			let foreground = try #require(attribute(
				.foregroundColor,
				in: text,
				at: "body"
			) as? NSColor)
			let link = try #require(attribute(
				.foregroundColor,
				in: text,
				at: "link"
			) as? NSColor)
			#expect(attribute(
				.conversationCodeBlockID,
				in: text,
				at: "code"
			) as? Int == 0)
			#expect(attribute(
				.conversationCodeLanguage,
				in: text,
				at: "code"
			) as? String == "text")
			let background = NSColor.controlBackgroundColor
			#expect(foreground == .labelColor)
			#expect(link == .linkColor)
			appearance.performAsCurrentDrawingAppearance
			{
				#expect(foreground.usingColorSpace(.deviceRGB) != background
					.usingColorSpace(.deviceRGB))
			}
		}
	}

	@Test func hardBreaksKeepLFWithoutParagraphGapsOrRepeatedListIndent() async throws
	{
		let content = await prepare("- **first  \n  second**\n\nordinary  \ncontinuation\n\nnext")
		let text = content.attributedString
		#expect(text.string == "• first\nsecond\nordinary\ncontinuation\nnext")
		let first = try paragraph(
			in: text,
			at: "first"
		)
		let second = try paragraph(
			in: text,
			at: "second"
		)
		#expect(first.paragraphSpacing == 0)
		#expect(first.firstLineHeadIndent < first.headIndent)
		#expect(second.firstLineHeadIndent == second.headIndent)
		#expect(second.headIndent == first.headIndent)
		#expect(second.paragraphSpacing == 5)
		#expect(try paragraph(
			in: text,
			at: "ordinary"
		).paragraphSpacing == 0)
		#expect(try paragraph(
			in: text,
			at: "continuation"
		).paragraphSpacing == 10)
		#expect(try paragraph(
			in: text,
			at: "next"
		).paragraphSpacing == 10)
		#expect(NSFontManager.shared.traits(of: try font(
			in: text,
			at: "second"
		))
		.contains(.boldFontMask))
	}

	@Test func nativeTableSpansSkipCoveredCellsAndPreserveColumnPositions() async throws
	{
		let content = await prepare("""
		| one | two | three |
		| --- | --- | ----- |
		| big || small |
		| ^ || small |

		After spans.
		""")
		let text = content.attributedString
		let bigStyle = try paragraph(
			in: text,
			at: "big"
		)
		let big = try #require(bigStyle.textBlocks.first as? NSTextTableBlock)
		#expect(big.startingRow == 1)
		#expect(big.startingColumn == 0)
		#expect(big.rowSpan == 2)
		#expect(big.columnSpan == 2)
		var cells: [NSTextTableBlock] = []
		text.enumerateAttribute(
			.paragraphStyle,
			in: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			value, _, _ in
			guard let style = value as? NSParagraphStyle,
					let cell = style.textBlocks.first as? NSTextTableBlock,
					!cells.contains(where:
					{
						$0 === cell
					})
			else
			{
				return
			}
			cells.append(cell)
		}
		#expect(cells.count == 6)
		let lastColumn = cells.filter
		{
			$0.startingRow > 0 && $0.startingColumn == 2
		}
		#expect(lastColumn.map(\.startingRow) == [1, 2])
		#expect(lastColumn.allSatisfy
		{
			$0.rowSpan == 1 && $0.columnSpan == 1
		})
		#expect(text.string == "one\ntwo\nthree\nbig\nsmall\nsmall\nAfter spans.")
		#expect(try paragraph(
			in: text,
			at: "After spans."
		).textBlocks.isEmpty)
	}

	@Test func nativeSelectionCopiesExactCodeToAnIsolatedPasteboard() async throws
	{
		_ = NSApplication.shared
		let body = "😀 predecessor\n\n```text\n  café 😀\tvalue  \n```"
		let content = await prepare(body)
		let item = makeItem(
			body: body,
			content: content
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 200
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = item
		window.setContentSize(NSSize(
			width: 320,
			height: 200
		))
		item.view.layoutSubtreeIfNeeded()
		let textView = try #require(findTextView(in: item.view))
		let range = try #require(content.codeBlockRanges.first)
		let code = try #require(content.codeBlocks.first)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		textView.setSelectedRange(range)
		#expect(textView.selectedRange() == range)
		#expect(textView.writeSelection(
			to: pasteboard,
			types: textView.writablePasteboardTypes
		))
		#expect(pasteboard.string(forType: .string) == "  café 😀\tvalue  \n")
		#expect(pasteboard.string(forType: .string) == code)
	}

	@Test func userBubblePreservesMarkdownAttributesLayoutAndExactCodeSelection() async throws
	{
		_ = NSApplication.shared
		let body = "# User heading\n\n**bold** and [site](https://example.com/path)\n\n"
			+ "- parent\n  - nested\n\n"
			+ "| Name | Value |\n| --- | --- |\n| item | 42 |\n\n"
			+ "```swift\n  let value = \"😀\"  \n```"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true,
			preserveSoftBreaks: true
		)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		for width: CGFloat in [320, 800]
		{
			let item = makeItem(
				body: body,
				content: content,
				kind: .user
			)
			let size = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false,
				kind: .user
			)
			let window = NSWindow(
				contentRect: NSRect(
					origin: .zero,
					size: size
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.contentViewController = item
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let textView = try #require(findTextView(in: item.view))
			let storage = try #require(textView.textStorage)
			// Compare with native font substitution, including the emoji fallback font.
			let referenceView = NSTextView(frame: textView.frame)
			let nativeReference = try #require(referenceView.textStorage)
			nativeReference.setAttributedString(content.attributedString)
			try #require(referenceView.layoutManager).ensureLayout(
				for: try #require(referenceView.textContainer)
			)
			#expect(storage == nativeReference)
			#expect(!textView.string.contains("# User heading"))
			#expect(textView.isSelectable && !textView.isEditable)
			#expect(try font(
				in: storage,
				at: "User heading"
			).pointSize
				== font(
					in: content.attributedString,
					at: "User heading"
				).pointSize)
			#expect(NSFontManager.shared.traits(of: try font(
				in: storage,
				at: "bold"
			))
			.contains(.boldFontMask))
			#expect((attribute(
				.link,
				in: storage,
				at: "site"
			) as? URL)?.absoluteString
				== "https://example.com/path")
			#expect(try paragraph(
				in: storage,
				at: "item"
			).textBlocks.first is NSTextTableBlock)
			#expect(try paragraph(
				in: storage,
				at: "nested"
			).headIndent
				> paragraph(
					in: storage,
					at: "parent"
				).headIndent)
			let realized = textView.convert(
				textView.bounds,
				to: item.view
			)
			#expect(item.view.bounds.contains(realized))
			#expect(realized.minX > 0 && realized.maxX < width)
			let layout = try #require(textView.layoutManager)
			let container = try #require(textView.textContainer)
			layout.ensureLayout(for: container)
			#expect(layout.usedRect(for: container).height <= textView.bounds.height)
			#expect(layout.usedRect(for: container).maxX <= textView.bounds.width + 0.5)
			let range = try #require(content.codeBlockRanges.first)
			#expect((textView.string as NSString).substring(with: range)
				== "  let value = \"😀\"  \n")
			textView.setSelectedRange(range)
			#expect(textView.writeSelection(
				to: pasteboard,
				types: textView.writablePasteboardTypes
			))
			#expect(pasteboard.string(forType: .string) == "  let value = \"😀\"  \n")
			#expect(allButtons(in: item.view).filter
			{
				($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
			}.count == 1)
		}
		#expect(body.hasPrefix("# User heading"))
		#expect(body.hasSuffix("```"))
	}

	@Test func codeCopyButtonTracksGlyphLineAfterUnicodeAndStructuredBlocks() async throws
	{
		_ = NSApplication.shared
		let body = String(
			repeating: "😀 café é 👨‍👩‍👧‍👦 ",
			count: 36
		) + """


		- list 中文

		> quote Ελληνικά with `inline code`

		| First | Second |
		| --- | --- |
		| 日本語 | 😀 |

		```text
		  exact 😀\tcode
		```
		"""
		let content = await prepare(body)
		let item = makeItem(
			body: body,
			content: content
		)
		let size = ConversationCollectionItem.itemSize(
			content: content,
			width: 320,
			expandable: false
		)
		let window = NSWindow(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = item
		window.setContentSize(size)
		item.view.layoutSubtreeIfNeeded()
		let textView = try #require(findTextView(in: item.view))
		let buttons = allButtons(in: item.view).filter
		{
			($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
		}
		try #require(buttons.count == 1)
		let range = try #require(content.codeBlockRanges.first)
		#expect((textView.string as NSString).substring(with: range) == "  exact 😀\tcode\n")
		let layout = try #require(textView.layoutManager)
		layout.ensureLayout(for: try #require(textView.textContainer))
		let glyphs = layout.glyphRange(
			forCharacterRange: range,
			actualCharacterRange: nil
		)
		let line = layout.lineFragmentRect(
			forGlyphAt: glyphs.location,
			effectiveRange: nil
		)
		let manager = try #require(layout as? ConversationMarkdownLayoutManager)
		let container = try #require(textView.textContainer)
		let header = try #require(manager.codeBlockHeaderRect(
			atCharacter: range.location,
			in: container
		))
		#expect(header.minY < line.minY)
		let buttonFrame = textView.convert(
			buttons[0].bounds,
			from: buttons[0]
		)
		#expect(abs(buttonFrame.midY - (textView.textContainerOrigin.y + header.midY)) < 0.5)
		#expect(buttons[0].superview !== textView)
		#expect(buttons[0].title.isEmpty && buttons[0].imagePosition == .imageOnly)
		#expect(buttonFrame.maxX <= textView.bounds.width)
	}

	@Test func nativeCodeCardsStaySeparateAndLeaveTheFollowingMarkerVisible() async throws
	{
		_ = NSApplication.shared
		let body = "```python\ndef greet(name):\n    return name\n```\n\n"
			+ "```swift\nlet message = \"😀 café\"\nprint(message)\n```\n\n"
			+ "    indented code\n    second line\n\nCODE_END_MARKER"
		let content = await prepare(body)
		try #require(content.codeBlockRanges.count == 3)
		for width: CGFloat in [320, 800]
		{
			let item = makeItem(
				body: body,
				content: content
			)
			let size = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false
			)
			let window = NSWindow(
				contentRect: NSRect(
					origin: .zero,
					size: size
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.contentViewController = item
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let textView = try #require(findTextView(in: item.view))
			let manager = try #require(textView.layoutManager as? ConversationMarkdownLayoutManager)
			let container = try #require(textView.textContainer)
			manager.ensureLayout(for: container)
			let buttons = allButtons(in: item.view).filter
			{
				($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
			}.sorted
			{
				$0.tag < $1.tag
			}
			try #require(buttons.count == 3)
			var cards: [NSRect] = []
			for (index, range) in content.codeBlockRanges.enumerated()
			{
				let card = try #require(manager.codeBlockRect(
					atCharacter: range.location,
					in: container
				))
				let header = try #require(manager.codeBlockHeaderRect(
					atCharacter: range.location,
					in: container
				))
				let buttonFrame = textView.convert(
					buttons[index].bounds,
					from: buttons[index]
				)
				#expect(abs(buttonFrame.midY
						- (textView.textContainerOrigin.y + header.midY)) < 0.5)
				#expect(card.contains(header))
				#expect(card.minX >= 0 && card.maxX <= container.size.width + 0.5)
				#expect((textView.string as NSString).substring(with: range)
					== content.codeBlocks[index])
				if let previous = cards.last
				{
					#expect(card.minY - previous.maxY >= 7.5)
				}
				cards.append(card)
			}
			let marker = (textView.string as NSString).range(of: "CODE_END_MARKER")
			let glyphs = manager.glyphRange(
				forCharacterRange: marker,
				actualCharacterRange: nil
			)
			let markerRect = manager.boundingRect(
				forGlyphRange: glyphs,
				in: container
			)
			#expect(markerRect.minY - (try #require(cards.last)).maxY >= 7.5)
			#expect(markerRect.maxY <= textView.bounds.height)
		}
	}

	@Test func closingQuoteRailLeavesSpaceBeforeCodeWithoutChangingCardGeometry() async throws
	{
		_ = NSApplication.shared
		let code = "let longLine = \"CODE_WRAP_MARKER — a long literal line with spaces, "
			+ "Unicode 👩🏽‍💻 café é 日本語, and punctuation * [ ] < > & that must remain "
			+ "inside its native code card.\"\n"
		let diagram = "flowchart LR\nA[Source] --> B[Parser] --> C[Content]\n"
		let diagramSource = "```mermaid\n" + diagram + "```"
		let firstQuote = "First quoted paragraph has enough words to wrap when the user bubble "
			+ "or conversation pane is narrow."
		let lastQuote = "A nested quotation remains inside the outer quote."
		let body = "# Native layout edge probes\n\n> " + firstQuote + "\n>\n"
			+ "> A second quoted paragraph should share the same continuous outer quote rail.\n"
			+ ">\n> > " + lastQuote + "\n\n```swift\n" + code + "```\n\n```text\n```\n\n"
			+ "EMPTY_FENCE_END_MARKER\n\n" + diagramSource + "\n\nFINAL_MARKER"
		let reference = await prepare(
			"```swift\n" + code + "```\n\n```text\n```\n\nEMPTY_FENCE_END_MARKER\n\n"
				+ diagramSource + "\n\nFINAL_MARKER"
		)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		for kind in [ConversationEntryKind.agent, .user]
		{
			let content = await ConversationContentCache().content(
				body: body,
				markdown: true,
				preserveSoftBreaks: kind == .user
			)
			#expect(content.codeBlocks == [code, "", diagram])
			try #require(content.codeBlockRanges.count == 3)
			let item = makeItem(
				body: body,
				content: content,
				kind: kind
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 320,
					height: 1000
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.contentViewController = item
			defer
			{
				window.contentViewController = nil
				window.isReleasedWhenClosed = false
				window.close()
			}
			for width: CGFloat in [320, 800, 320]
			{
				window.setContentSize(ConversationCollectionItem.itemSize(
					content: content,
					width: width,
					expandable: false,
					kind: kind
				))
				item.view.layoutSubtreeIfNeeded()
				let text = try #require(findTextView(in: item.view))
				let storage = try #require(text.textStorage)
				let manager = try #require(text.layoutManager as? ConversationMarkdownLayoutManager)
				let container = try #require(text.textContainer)
				manager.ensureLayout(for: container)
				let nativeReference = makeNativeLayout(
					reference.attributedString,
					width: container.size.width
				)
				let referenceManager = try #require(
					nativeReference.manager as? ConversationMarkdownLayoutManager
				)
				let first = (text.string as NSString).range(of: firstQuote)
				let last = (text.string as NSString).range(of: lastQuote)
				try #require(first.location != NSNotFound && last.location != NSNotFound)
				var finalQuoteStyle = NSRange()
				#expect(storage.attribute(
					.conversationQuoteRailOffsets,
					at: last.location,
					effectiveRange: &finalQuoteStyle
				) as? [Int] == [0, 16])
				let quoteRange = NSRange(
					location: first.location,
					length: NSMaxRange(finalQuoteStyle) - first.location
				)
				storage.enumerateAttribute(
					.conversationQuoteRailOffsets,
					in: quoteRange
				)
				{
					value, _, _ in
					#expect((value as? [Int])?.contains(0) == true)
				}
				let rail = try #require(manager.quoteRailRect(
					forCharacterRange: quoteRange,
					in: container
				))
				let quotedGlyphs = manager.glyphRange(
					forCharacterRange: last,
					actualCharacterRange: nil
				)
				let quotedBottom = manager.lineFragmentUsedRect(
					forGlyphAt: NSMaxRange(quotedGlyphs) - 1,
					effectiveRange: nil
				).maxY
				#expect(rail.maxY >= quotedBottom - 0.5)
				let nestedRail = try #require(manager.quoteRailRect(
					forCharacterRange: finalQuoteStyle,
					railOffset: 16,
					in: container
				))
				#expect(nestedRail.maxY >= quotedBottom - 0.5)
				let buttons = allButtons(in: item.view).filter
				{
					($0.accessibilityLabel() ?? "").hasPrefix("Copy code block ")
				}.sorted
				{
					$0.tag < $1.tag
				}
				try #require(buttons.count == 3)
				var cards: [NSRect] = []
				for (index, range) in content.codeBlockRanges.enumerated()
				{
					let card = try #require(manager.codeBlockRect(
						atCharacter: range.location,
						in: container
					))
					let header = try #require(manager.codeBlockHeaderRect(
						atCharacter: range.location,
						in: container
					))
					let referenceHeader = try #require(referenceManager.codeBlockHeaderRect(
						atCharacter: reference.codeBlockRanges[index].location,
						in: nativeReference.container
					))
					#expect(abs(header.height - referenceHeader.height) < 0.5)
					var blockRange = NSRange()
					_ = storage.attribute(
						.conversationCodeBlockID,
						at: range.location,
						longestEffectiveRange: &blockRange,
						in: NSRange(
							location: 0,
							length: storage.length
						)
					)
					let headerStyle = try #require(storage.attribute(
						.paragraphStyle,
						at: blockRange.location,
						effectiveRange: nil
					) as? NSParagraphStyle)
					#expect(headerStyle.minimumLineHeight == 44)
					#expect(headerStyle.maximumLineHeight == 44)
					#expect(card.contains(header))
					#expect(buttons[index].tag == index)
					#expect(header.offsetBy(
						dx: text.textContainerOrigin.x,
						dy: text.textContainerOrigin.y
					).contains(text.convert(
						buttons[index].bounds,
						from: buttons[index]
					)))
					if let previous = cards.last
					{
						#expect(card.minY - previous.maxY >= 7.5)
					}
					else
					{
						#expect(card.minY - rail.maxY >= 7.5)
						#expect(card.minY - nestedRail.maxY >= 7.5)
					}
					if index < 2
					{
						#expect((text.string as NSString).substring(with: range)
							== content.codeBlocks[index])
					}
					if index != 1
					{
						text.setSelectedRange(range)
						#expect(text.writeSelection(
							to: pasteboard,
							types: text.writablePasteboardTypes
						))
						#expect(pasteboard
							.string(forType: .string) == (index == 0 ? code : diagramSource))
					}
					cards.append(card)
				}
				for (marker, cardIndex) in [("EMPTY_FENCE_END_MARKER", 1), ("FINAL_MARKER", 2)]
				{
					let range = (text.string as NSString).range(of: marker)
					let glyphs = manager.glyphRange(
						forCharacterRange: range,
						actualCharacterRange: nil
					)
					let bounds = manager.boundingRect(
						forGlyphRange: glyphs,
						in: container
					)
					#expect(bounds.minY - cards[cardIndex].maxY >= 7.5)
					#expect(bounds.maxY <= text.bounds.height)
				}
			}
		}
		try await assertClosingQuotedCodeKeepsItsFooterInsideTheRail()
	}

	@Test func explicitNativeSelectionAndVisibilityScrollingStillReachRequestedText() throws
	{
		_ = NSApplication.shared
		let textView = ConversationMarkdownTextView(frame: NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 3000
		))
		textView.isEditable = false
		textView.isSelectable = true
		textView.isVerticallyResizable = false
		textView.textContainerInset = .zero
		textView.string = (0 ..< 100).map
		{
			"Native line \($0) with readable text."
		}.joined(separator: "\n")
		let scroll = NSScrollView(frame: NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 140
		))
		scroll.documentView = textView
		scroll.contentView.scroll(to: .zero)
		let manager = try #require(textView.layoutManager)
		let container = try #require(textView.textContainer)
		manager.ensureLayout(for: container)
		let range = (textView.string as NSString).range(of: "Native line 99")
		let glyphs = manager.glyphRange(
			forCharacterRange: range,
			actualCharacterRange: nil
		)
		let destination = manager.boundingRect(
			forGlyphRange: glyphs,
			in: container
		)
		textView.setSelectedRange(range)
		textView.scrollRangeToVisible(range)
		#expect(textView.selectedRange() == range)
		#expect(scroll.contentView.bounds.minY > 0)
		#expect(destination.intersects(scroll.contentView.bounds))
		let first = manager.lineFragmentRect(
			forGlyphAt: 0,
			effectiveRange: nil
		)
		#expect(textView.scrollToVisible(first))
		#expect(first.intersects(scroll.contentView.bounds))
		#expect(scroll.contentView.bounds.minY == 0)
	}

	private func assertClosingQuotedCodeKeepsItsFooterInsideTheRail() async throws
	{
		for code in ["  quoted 😀 code\n", ""]
		{
			let quotedLines = code.split(
				separator: "\n",
				omittingEmptySubsequences: true
			).map
			{
				"> " + $0 + "\n"
			}.joined()
			let content = await prepare(
				"> ```text\n" + quotedLines + "> ```\n\nAFTER_QUOTED_CODE_MARKER"
			)
			#expect(content.codeBlocks == [code])
			let codeRange = try #require(content.codeBlockRanges.first)
			for width: CGFloat in [320, 800]
			{
				let native = makeNativeLayout(
					content.attributedString,
					width: width
				)
				let manager = try #require(native.manager as? ConversationMarkdownLayoutManager)
				var quoteRange = NSRange()
				#expect(native.storage.attribute(
					.conversationQuoteRailOffsets,
					at: codeRange.location,
					longestEffectiveRange: &quoteRange,
					in: NSRange(
						location: 0,
						length: native.storage.length
					)
				) as? [Int] == [0])
				let rail = try #require(manager.quoteRailRect(
					forCharacterRange: quoteRange,
					in: native.container
				))
				let card = try #require(manager.codeBlockRect(
					atCharacter: codeRange.location,
					in: native.container
				))
				#expect(rail.minY <= card.minY + 0.5)
				#expect(rail.maxY >= card.maxY - 0.5)
				let marker = (native.storage.string as NSString)
					.range(of: "AFTER_QUOTED_CODE_MARKER")
				let glyphs = manager.glyphRange(
					forCharacterRange: marker,
					actualCharacterRange: nil
				)
				let markerRect = manager.boundingRect(
					forGlyphRange: glyphs,
					in: native.container
				)
				#expect(markerRect.minY - rail.maxY >= 7.5)
				#expect((native.storage.string as NSString).substring(with: codeRange) == code)
			}
		}
	}

	private func prepare(_ body: String) async -> PreparedConversationContent
	{
		await ConversationContentCache().content(
			body: body,
			markdown: true
		)
	}

	private func makeNativeLayout(
		_ text: NSAttributedString,
		width: CGFloat
	) -> (storage: NSTextStorage, manager: NSLayoutManager, container: NSTextContainer)
	{
		let storage = NSTextStorage(attributedString: text)
		let manager = ConversationMarkdownLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: width,
			height: .greatestFiniteMagnitude
		))
		container.lineFragmentPadding = 0
		storage.addLayoutManager(manager)
		manager.addTextContainer(container)
		manager.ensureLayout(for: container)
		return (storage, manager, container)
	}

	private func lineRect(
		at characterLocation: Int,
		layout: NSLayoutManager
	) -> NSRect
	{
		layout.lineFragmentRect(
			forGlyphAt: layout.glyphIndexForCharacter(at: characterLocation),
			effectiveRange: nil
		)
	}

	private func makeItem(
		body: String,
		content: PreparedConversationContent,
		kind: ConversationEntryKind = .agent
	) -> ConversationCollectionItem
	{
		let item = ConversationCollectionItem()
		item.configure(
			ConversationEntry(
				id: "markdown",
				kind: kind,
				title: "Codex",
				body: body
			),
			content: content,
			expanded: true,
			onToggle:
			{
			}
		)
		return item
	}

	private func attribute(
		_ key: NSAttributedString.Key,
		in text: NSAttributedString,
		at substring: String
	) -> Any?
	{
		let range = (text.string as NSString).range(of: substring)
		guard range.location != NSNotFound
		else
		{
			Issue.record("Missing rendered text: \(substring)")
			return nil
		}
		return text.attribute(
			key,
			at: range.location,
			effectiveRange: nil
		)
	}

	private func font(
		in text: NSAttributedString,
		at substring: String
	) throws -> NSFont
	{
		try #require(attribute(
			.font,
			in: text,
			at: substring
		) as? NSFont)
	}

	private func paragraph(
		in text: NSAttributedString,
		at substring: String
	) throws -> NSParagraphStyle
	{
		try #require(attribute(
			.paragraphStyle,
			in: text,
			at: substring
		) as? NSParagraphStyle)
	}

	private func findTextView(in view: NSView) -> NSTextView?
	{
		if let textView = view as? NSTextView
		{
			return textView
		}
		return view.subviews.lazy.compactMap
		{
			findTextView(in: $0)
		}.first
	}

	private func allButtons(in view: NSView) -> [NSButton]
	{
		((view as? NSButton).map
		{
			[$0]
		} ?? []) + view.subviews.flatMap
		{
			allButtons(in: $0)
		}
	}
}
