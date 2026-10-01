import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationRichMarkdownTests
{
	@Test func mathImagesRenderRawTeXAndRejectInvalidCommandsInBothAppearances() throws
	{
		_ = NSApplication.shared
		for dark in [false, true]
		{
			let image = try #require(ConversationRichBlockRenderer.mathImage(
				#"\int_0^1 x^2\,dx = \frac{1}{3}"#,
				dark: dark
			))
			#expect(image.size.width > 0 && image.size.height > 0)
			#expect(ConversationRichBlockRenderer.mathImage(
				#"\definitelyUnknownCommand{x}"#,
				dark: dark
			) == nil)
		}
	}

	@Test func nativeFlowchartImagesRenderSupportedGraphsAndRejectUnsupportedSyntax() throws
	{
		_ = NSApplication.shared
		let source = "flowchart LR\n    A[Markdown source] --> B[Parser]\n"
			+ "    B --> C[Rendered content]\n"
		for dark in [false, true]
		{
			let image = try #require(ConversationRichBlockRenderer.diagramImage(
				source,
				dark: dark
			))
			#expect(image.size.width > 0 && image.size.height > 0)
			#expect(ConversationRichBlockRenderer.diagramImage(
				"sequenceDiagram\nAlice->>Bob: Hello",
				dark: dark
			) == nil)
			#expect(ConversationRichBlockRenderer.diagramImage(
				"flowchart LR\nA[Missing bracket --> B[Result]",
				dark: dark
			) == nil)
			#expect(ConversationRichBlockRenderer.diagramImage(
				"flowchart LR\nA[\"unfinished] --> B",
				dark: dark
			) == nil)
		}
	}

	@Test func failedMathRenderingRetainsItsSourceAndWrapsTheNativeFallback() throws
	{
		_ = NSApplication.shared
		let payload = #"\definitelyUnknownCommand{"# + String(
			repeating: "x",
			count: 120
		) + "}"
		let source = "$$\n" + payload + "\n$$"
		let attachment = ConversationRichBlockRenderer.mathAttachment(
			latex: payload,
			source: source
		)
		let rich = try #require(attachment as? ConversationRichAttachment)
		#expect(!rich.rendersNativeImage)
		#expect(rich.estimatedRichImageBytes == 0)
		#expect(rich.source == source)
		let cell = try #require(attachment.attachmentCell)
		var heights: [CGFloat] = []
		for width: CGFloat in [240, 640]
		{
			let container = NSTextContainer(size: NSSize(
				width: width,
				height: 1000
			))
			container.lineFragmentPadding = 0
			let frame = cell.cellFrame(
				for: container,
				proposedLineFragment: NSRect(
					x: 0,
					y: 0,
					width: width,
					height: 24
				),
				glyphPosition: .zero,
				characterIndex: 0
			)
			#expect(frame.width <= width && frame.height > 0)
			heights.append(frame.height)
		}
		#expect(heights[0] > heights[1])
	}

	@Test func unsupportedDiagramLineSeparatorsKeepEveryStatementInSourceFallback()
		async throws
	{
		_ = NSApplication.shared
		for separator in ["\u{2028}", "\u{2029}"]
		{
			let code = "flowchart LR\nA --> B" + separator + "C --> D\n"
			#expect(ConversationRichBlockRenderer.diagramImage(
				code,
				dark: false
			) == nil)
			let source = "```mermaid\n" + code + "```"
			let content = await ConversationContentCache().content(
				body: source,
				markdown: true
			)
			let range = try #require(content.codeBlockRanges.first)
			let attachment = try #require(content.attributedString.attribute(
				.attachment,
				at: range.location,
				effectiveRange: nil
			) as? ConversationRichAttachment)
			#expect(!attachment.rendersNativeImage)
			#expect(attachment.source == source)
			#expect(content.codeBlocks == [code])
			let textView = ConversationMarkdownTextView(frame: .zero)
			try #require(textView.textStorage).setAttributedString(content.attributedString)
			textView.setSelectedRange(range)
			let pasteboard = NSPasteboard.withUniqueName()
			defer
			{
				pasteboard.releaseGlobally()
			}
			#expect(textView.writeSelection(
				to: pasteboard,
				type: .string
			))
			#expect(pasteboard.string(forType: .string) == source)
		}
	}

	@Test func highlightingPreservesExactUnicodeCodeWhileAddingTokenColors() throws
	{
		_ = NSApplication.shared
		let source = "let message = \"café 😀\"\n// Unicode comment 日本語\nprint(message)\n"
		for dark in [false, true]
		{
			let highlighted = try #require(ConversationCodeHighlighter.highlightedCode(
				source,
				language: "swift",
				dark: dark
			))
			#expect(highlighted.string.utf8.elementsEqual(source.utf8))
			var colors = Set<NSColor>()
			highlighted.enumerateAttribute(
				.foregroundColor,
				in: NSRange(
					location: 0,
					length: highlighted.length
				)
			)
			{
				value, _, _ in
				if let color = value as? NSColor
				{
					colors.insert(color)
				}
			}
			#expect(colors.count > 1)
		}
	}

	@Test func cachedHighlightedCodeResolvesItsTokenColorsInBothAppearances() async throws
	{
		_ = NSApplication.shared
		let content = await ConversationContentCache().content(
			body: "```swift\nlet value = 42\n```",
			markdown: true
		)
		let text = content.attributedString
		let range = (text.string as NSString).range(of: "let")
		let color = try #require(text.attribute(
			.foregroundColor,
			at: range.location,
			effectiveRange: nil
		) as? NSColor)
		var resolved: [NSColor] = []
		for name in [NSAppearance.Name.aqua, .darkAqua]
		{
			let appearance = try #require(NSAppearance(named: name))
			appearance.performAsCurrentDrawingAppearance
			{
				if let token = color.usingColorSpace(.deviceRGB)
				{
					#expect(token != NSColor.labelColor.usingColorSpace(.deviceRGB))
					resolved.append(token)
				}
			}
		}
		try #require(resolved.count == 2)
		#expect(resolved[0] != resolved[1])
		#expect(content.codeBlocks == ["let value = 42\n"])
		#expect((text.string as NSString)
			.substring(with: try #require(content.codeBlockRanges.first))
			== content.codeBlocks[0])
	}

	@Test func richNativeSelectionCopiesExactSourcesAndAccessibilityUsesOneCoordinateSpace()
		async throws
	{
		_ = NSApplication.shared
		let math = "$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$"
		let diagram = "```mermaid\nflowchart LR\n    A[Source] --> B[Result]\n```"
		let body = "Before 😀\n\n" + math + "\n\n" + diagram + "\n\nAfter café"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true,
			preserveSoftBreaks: true
		)
		let textView = ConversationMarkdownTextView(frame: NSRect(
			x: 0,
			y: 0,
			width: 640,
			height: 600
		))
		textView.isEditable = false
		textView.isSelectable = true
		try #require(textView.textStorage).setAttributedString(content.attributedString)
		textView.updateSourceAccessibilityHelp()
		let window = NSWindow(
			contentRect: textView.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.contentView = textView
		window.setContentSize(textView.frame.size)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		var selections: [(NSRange, String)] = []
		content.attributedString.enumerateAttribute(
			.conversationSourceText,
			in: NSRange(
				location: 0,
				length: content.attributedString.length
			)
		)
		{
			value, range, _ in
			if let source = value as? String
			{
				selections.append((range, source))
			}
		}
		#expect(selections.map(\.1) == [math, diagram])
		for (range, source) in selections
		{
			#expect(range.length == 1)
			textView.setSelectedRange(range)
			for types in [textView.writablePasteboardTypes, [.string]]
			{
				#expect(textView.writeSelection(
					to: pasteboard,
					types: types
				))
				#expect(pasteboard.string(forType: .string) == source)
			}
		}
		let accessible = try #require(textView.accessibilityValue())
		#expect(accessible == textView.string)
		#expect(textView.accessibilityNumberOfCharacters() == accessible.utf16.count)
		let help = try #require(textView.accessibilityHelp())
		#expect(help.contains(math) && help.contains(diagram))
		let nativeTail = (textView.string as NSString).range(of: "After café")
		let accessibleTail = (accessible as NSString).range(of: "After café")
		textView.setSelectedRange(nativeTail)
		#expect(textView.accessibilitySelectedTextRange() == accessibleTail)
		#expect(textView.accessibilityString(for: accessibleTail) == "After café")
		textView.setSelectedRange(NSRange(
			location: 0,
			length: textView.string.utf16.count
		))
		#expect(textView.writeSelection(
			to: pasteboard,
			types: textView.writablePasteboardTypes
		))
		#expect(pasteboard.string(forType: .string) == "Before 😀\n" + math + "\n"
			+ diagram + "\nAfter café")
		try #require(textView.textStorage).setAttributedString(NSAttributedString(string: "Plain"))
		textView.updateSourceAccessibilityHelp()
		#expect(textView.accessibilityHelp() == nil)
	}

	@Test func manyRichBlocksStayWithinImageBudgetAndKeepLateSourceSelectable() async throws
	{
		_ = NSApplication.shared
		let sources = (0 ..< 40).map
		{
			"```mermaid\nflowchart LR\nA[Block \($0)] --> B[Result]\n```"
		}
		let body = sources.joined(separator: "\n\n") + "\n\nFINAL_MARKER 😀"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let text = content.attributedString
		var attachments: [(NSRange, ConversationRichAttachment)] = []
		text.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			value, range, _ in
			if let attachment = value as? ConversationRichAttachment
			{
				attachments.append((range, attachment))
			}
		}
		try #require(attachments.count == sources.count)
		#expect(attachments[0].1.rendersNativeImage)
		#expect(attachments[0].1.estimatedRichImageBytes > 0)
		#expect(attachments.reduce(0)
		{
			$0 + $1.1.estimatedRichImageBytes
		} <= 8_000_000)
		#expect(attachments.filter
		{
			$0.1.rendersNativeImage
		}.count <= 32)
		let last = try #require(attachments.last)
		#expect(!last.1.rendersNativeImage)
		#expect(last.1.estimatedRichImageBytes == 0)
		#expect(last.1.source == sources.last)
		#expect(text.string.hasSuffix("FINAL_MARKER 😀"))
		let textView = ConversationMarkdownTextView(frame: .zero)
		try #require(textView.textStorage).setAttributedString(text)
		textView.setSelectedRange(last.0)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		#expect(textView.writeSelection(
			to: pasteboard,
			type: .string
		))
		#expect(pasteboard.string(forType: .string) == sources.last)
		#expect(ConversationPlainTextRenderer.render(
			ConversationContentParser.parse(
				body,
				markdown: true
			)
		).hasSuffix(try #require(sources.last) + "\n\nFINAL_MARKER 😀"))
	}

	@Test func richImageCostsEvictCachedMessagesBeforeTheEntryLimit() async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		let firstSource = "```mermaid\nflowchart LR\nA[First cached source] --> B[Result]\n```"
		let first = await cache.content(
			body: firstSource,
			markdown: true
		)
		try #require(first.estimatedRichImageBytes > 0)
		#expect(await cache.content(
			body: firstSource,
			markdown: true
		) === first)
		let capacity = 6 * 1024 * 1024
		var aggregateCost = firstSource.utf8.count + first.estimatedRichImageBytes
		var sourceBytes = firstSource.utf8.count
		var latestSource = firstSource
		var latest = first
		for index in 0 ..< 32
		{
			latestSource = "```mermaid\nflowchart LR\n"
				+ "A[Independent message \(index)] --> B[Cache pressure]\n```"
			latest = await cache.content(
				body: latestSource,
				markdown: true
			)
			try #require(latest.estimatedRichImageBytes > 0)
			aggregateCost += latestSource.utf8.count + latest.estimatedRichImageBytes
			sourceBytes += latestSource.utf8.count
			if aggregateCost > capacity
			{
				break
			}
		}
		try #require(aggregateCost > capacity)
		#expect(sourceBytes < capacity)
		#expect(await cache.content(
			body: latestSource,
			markdown: true
		) === latest)
		let reloadedFirst = await cache.content(
			body: firstSource,
			markdown: true
		)
		#expect(reloadedFirst !== first)
		#expect(reloadedFirst.codeBlocks == first.codeBlocks)
		#expect(reloadedFirst.attributedString.string == first.attributedString.string)
	}

	@Test func actualTextKitRichAttachmentsFitAfterResizeAndMathStaysCentered() async throws
	{
		_ = NSApplication.shared
		let body = "$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$\n\n"
			+ "```mermaid\nflowchart LR\n"
			+ "A[Markdown source] --> B[Parser] --> C[Rendered content] --> D[Selection]\n```"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let storage = NSTextStorage(attributedString: content.attributedString)
		let manager = ConversationMarkdownLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: 320,
			height: 10_000
		))
		container.lineFragmentPadding = 0
		container.widthTracksTextView = false
		container.heightTracksTextView = false
		manager.addTextContainer(container)
		storage.addLayoutManager(manager)
		let textView = ConversationMarkdownTextView(
			frame: NSRect(
				x: 0,
				y: 0,
				width: 320,
				height: 10_000
			),
			textContainer: container
		)
		textView.textContainerInset = .zero
		var ranges: [NSRange] = []
		storage.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: storage.length
			)
		)
		{
			value, range, _ in
			if let attachment = value as? ConversationRichAttachment
			{
				#expect(attachment.rendersNativeImage)
				ranges.append(range)
			}
		}
		try #require(ranges.count == 2)
		var diagramWidths: [CGFloat] = []
		for width: CGFloat in [320, 800, 320]
		{
			textView.setFrameSize(NSSize(
				width: width,
				height: 10_000
			))
			container.size = NSSize(
				width: width,
				height: 10_000
			)
			manager.ensureLayout(for: container)
			for (index, range) in ranges.enumerated()
			{
				let glyphs = manager.glyphRange(
					forCharacterRange: range,
					actualCharacterRange: nil
				)
				let size = manager.attachmentSize(forGlyphAt: glyphs.location)
				let rect = manager.boundingRect(
					forGlyphRange: glyphs,
					in: container
				)
				let paragraph = try #require(storage.attribute(
					.paragraphStyle,
					at: range.location,
					effectiveRange: nil
				) as? NSParagraphStyle)
				#expect(size.width > 0 && size.height > 0)
				#expect(rect.minX >= paragraph.headIndent - 0.5)
				#expect(rect.maxX <= width + paragraph.tailIndent + 0.5)
				#expect(size.width <= width - paragraph.headIndent + paragraph.tailIndent + 0.5)
				if index == 0
				{
					#expect(abs(rect.midX - width / 2) <= 1)
				}
				else
				{
					diagramWidths.append(size.width)
				}
			}
		}
		#expect(diagramWidths[1] > diagramWidths[0])
		#expect(abs(diagramWidths[0] - diagramWidths[2]) < 0.5)
	}
}
