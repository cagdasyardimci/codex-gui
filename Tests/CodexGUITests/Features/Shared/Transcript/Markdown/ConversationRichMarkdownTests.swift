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
			let image = try #require(MarkdownRichBlockRenderer.mathImage(
				#"\int_0^1 x^2\,dx = \frac{1}{3}"#,
				dark: dark
			))
			#expect(image.size.width > 0 && image.size.height > 0)
			#expect(MarkdownRichBlockRenderer.mathImage(
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
			let image = try #require(MarkdownRichBlockRenderer.diagramImage(
				source,
				dark: dark
			))
			#expect(image.size.width > 0 && image.size.height > 0)
			#expect(MarkdownRichBlockRenderer.diagramImage(
				"sequenceDiagram\nAlice->>Bob: Hello",
				dark: dark
			) == nil)
			#expect(MarkdownRichBlockRenderer.diagramImage(
				"flowchart LR\nA[Missing bracket --> B[Result]",
				dark: dark
			) == nil)
			#expect(MarkdownRichBlockRenderer.diagramImage(
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
		let attachment = MarkdownRichBlockRenderer.mathAttachment(
			latex: payload,
			source: source
		)
		let rich = try #require(attachment as? MarkdownRichAttachment)
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

	@Test func attachmentCellPaintsItsAppearancePatternWithinCenteredFittedMargins() throws
	{
		_ = NSApplication.shared
		let attachment = MarkdownRichAttachment(
			source: "Independent painted fixture",
			lightImage: try patternedImage(
				leftRGBA: [255, 0, 0, 255],
				rightRGBA: [0, 255, 0, 255]
			),
			darkImage: try patternedImage(
				leftRGBA: [0, 0, 255, 255],
				rightRGBA: [255, 255, 0, 255]
			)
		)
		let cell = try #require(attachment.attachmentCell)
		let control = NSView()
		// A 120 by 60 source stays natural at width 160 and halves both axes at width 60.
		let cases: [(CGFloat, NSRect)] = [
			(160, NSRect(
				x: 32,
				y: 30,
				width: 120,
				height: 60
			)),
			(60, NSRect(
				x: 12,
				y: 45,
				width: 60,
				height: 30
			))
		]
		for (width, paintedFrame) in cases
		{
			let cellFrame = NSRect(
				x: 12,
				y: 10,
				width: width,
				height: 100
			)
			for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				control.appearance = try #require(NSAppearance(named: name))
				let bitmap = try paintCell(
					cell,
					frame: cellFrame,
					control: control
				)
				let left = try pixel(
					bitmap,
					x: paintedFrame.minX + paintedFrame.width / 4,
					y: paintedFrame.midY
				)
				let right = try pixel(
					bitmap,
					x: paintedFrame.minX + paintedFrame.width * 3 / 4,
					y: paintedFrame.midY
				)
				if name == .aqua
				{
					#expect(left.redComponent > 0.9 && left.greenComponent < 0.1
						&& left.blueComponent < 0.1)
					#expect(right.redComponent < 0.1 && right.greenComponent > 0.9
						&& right.blueComponent < 0.1)
				}
				else
				{
					#expect(left.redComponent < 0.1 && left.greenComponent < 0.1
						&& left.blueComponent > 0.9)
					#expect(right.redComponent > 0.9 && right.greenComponent > 0.9
						&& right.blueComponent < 0.1)
				}
				for point in [
					NSPoint(
						x: paintedFrame.minX - 3,
						y: paintedFrame.midY
					),
					NSPoint(
						x: paintedFrame.maxX + 3,
						y: paintedFrame.midY
					),
					NSPoint(
						x: paintedFrame.midX,
						y: paintedFrame.minY - 3
					),
					NSPoint(
						x: paintedFrame.midX,
						y: paintedFrame.maxY + 3
					)
				]
				{
					let margin = try pixel(
						bitmap,
						x: point.x,
						y: point.y
					)
					#expect(margin.redComponent > 0.99 && margin.greenComponent > 0.99
						&& margin.blueComponent > 0.99 && margin.alphaComponent > 0.99)
				}
			}
		}
	}

	@Test func unsupportedDiagramLineSeparatorsKeepEveryStatementInSourceFallback()
		async throws
	{
		_ = NSApplication.shared
		for separator in ["\u{2028}", "\u{2029}"]
		{
			let code = "flowchart LR\nA --> B" + separator + "C --> D\n"
			#expect(MarkdownRichBlockRenderer.diagramImage(
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
			) as? MarkdownRichAttachment)
			#expect(!attachment.rendersNativeImage)
			#expect(attachment.source == source)
			#expect(content.codeBlocks == [code])
			let textView = MarkdownTextView(frame: .zero)
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
		let textView = MarkdownTextView(frame: NSRect(
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
		window.isReleasedWhenClosed = false
		window.contentView = textView
		defer
		{
			window.contentView = nil
			window.close()
		}
		window.setContentSize(textView.frame.size)
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		var selections: [(NSRange, String)] = []
		content.attributedString.enumerateAttribute(
			.markdownSourceText,
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
		var attachments: [(NSRange, MarkdownRichAttachment)] = []
		text.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			value, range, _ in
			if let attachment = value as? MarkdownRichAttachment
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
		let textView = MarkdownTextView(frame: .zero)
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
		#expect(MarkdownPlainTextRenderer.render(
			MarkdownContentParser.parse(
				body,
				markdown: true
			)
		).hasSuffix(try #require(sources.last) + "\n\nFINAL_MARKER 😀"))
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
		let manager = MarkdownLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: 320,
			height: 10_000
		))
		container.lineFragmentPadding = 0
		container.widthTracksTextView = false
		container.heightTracksTextView = false
		manager.addTextContainer(container)
		storage.addLayoutManager(manager)
		let textView = MarkdownTextView(
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
			if let attachment = value as? MarkdownRichAttachment
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

	private func patternedImage(
		leftRGBA: [UInt8],
		rightRGBA: [UInt8]
	) throws -> NSImage
	{
		let bytes = Data((0 ..< 120 * 60).flatMap
		{
			$0 % 120 < 60 ? leftRGBA : rightRGBA
		})
		let provider = try #require(CGDataProvider(data: bytes as CFData))
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let image = try #require(CGImage(
			width: 120,
			height: 60,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: 120 * 4,
			space: colorSpace,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		))
		return NSImage(
			cgImage: image,
			size: NSSize(
				width: 120,
				height: 60
			)
		)
	}

	private func paintCell(
		_ cell: NSTextAttachmentCellProtocol,
		frame: NSRect,
		control: NSView
	) throws -> CGContext
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: Int(frame.maxX + 12),
			height: 120,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
				| CGBitmapInfo.byteOrder32Big.rawValue
		))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = NSGraphicsContext(
			cgContext: context,
			flipped: false
		)
		context.setFillColor(
			red: 1,
			green: 1,
			blue: 1,
			alpha: 1
		)
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: CGFloat(context.width),
			height: CGFloat(context.height)
		))
		control.effectiveAppearance.performAsCurrentDrawingAppearance
		{
			cell.draw(
				withFrame: frame,
				in: control
			)
		}
		return context
	}

	private func pixel(
		_ bitmap: CGContext,
		x: CGFloat,
		y: CGFloat
	) throws -> NSColor
	{
		let bytes = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
		let offset = Int(y) * bitmap.bytesPerRow + Int(x) * 4
		// The fixture and destination are opaque sRGB; inspect ordered bytes directly.
		return NSColor(
			srgbRed: CGFloat(bytes[offset]) / 255,
			green: CGFloat(bytes[offset + 1]) / 255,
			blue: CGFloat(bytes[offset + 2]) / 255,
			alpha: CGFloat(bytes[offset + 3]) / 255
		)
	}
}
