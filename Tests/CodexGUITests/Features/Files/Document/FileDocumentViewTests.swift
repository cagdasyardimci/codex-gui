import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct FileDocumentViewTests
{
	@Test func sourceCopyExcludesRulerAndRetainsExactSeparators() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			let text = "😀 first\r\nsecond\u{2028}\n"
			source.render(
				text: text,
				path: "sample.swift",
				editable: true
			)
			#expect(source.textView.string == text)
			#expect(source.textView.textStorage?.string == text)
			#expect(SourceLineIndex(text).lineStarts.count == 4)
			let range = NSRange(
				location: 2,
				length: (text as NSString).length - 2
			)
			source.textView.setSelectedRange(range)
			#expect((source.textView.string as NSString).substring(with: range)
				== " first\r\nsecond\u{2028}\n")
			#expect(source.subviews.count == 1)
		}
	}

	@Test func markdownSourceSpacingGutterAndColorsFollowAppearanceAndEditing() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			let markdown = "# Heading\n- plain **strong** and *emphasis* with `code`\n"
				+ "```md\n# literal code\n```\nordinary text"
			source.render(
				text: markdown,
				path: "sample.md",
				editable: true
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 420,
					height: 300
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = source
			defer
			{
				window.close()
			}
			window.makeKeyAndOrderFront(nil)
			let text = source.textView
			let storage = try #require(text.textStorage)
			let manager = try #require(text.layoutManager)
			let container = try #require(text.textContainer)
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				source.layoutSubtreeIfNeeded()
				manager.ensureLayout(for: container)
				let first = manager.lineFragmentRect(
					forGlyphAt: manager.glyphIndexForCharacter(at: 0),
					effectiveRange: nil
				)
				let second = manager.lineFragmentRect(
					forGlyphAt: manager.glyphIndexForCharacter(at: 10),
					effectiveRange: nil
				)
				#expect(abs(second.minY - first.minY - 22) < 1)
				let glyph = manager.boundingRect(
					forGlyphRange: NSRange(
						location: 0,
						length: 1
					),
					in: container
				)
				let firstInSource = text.convert(
					NSPoint(
						x: glyph.minX + text.textContainerOrigin.x,
						y: 0
					),
					to: source
				)
				#expect((43 ... 49).contains(firstInSource.x))
				let headingColor = try #require(color(
					in: storage,
					matching: "Heading"
				))
				let listColor = try #require(color(
					in: storage,
					matching: "- plain"
				))
				let codeColor = try #require(color(
					in: storage,
					matching: "`code`"
				))
				let strongColor = try #require(color(
					in: storage,
					matching: "**strong**"
				))
				let emphasisColor = try #require(color(
					in: storage,
					matching: "*emphasis*"
				))
				let emphasisTextColor = try #require(color(
					in: storage,
					matching: "emphasis"
				))
				let connectiveColor = try #require(color(
					in: storage,
					matching: " and "
				))
				let literalColor = try #require(color(
					in: storage,
					matching: "# literal"
				))
				#expect(isRed(headingColor))
				#expect(isRed(listColor))
				#expect(isGreen(codeColor))
				#expect(isOrange(strongColor))
				#expect(isOrange(emphasisColor))
				#expect(isOrange(emphasisTextColor))
				#expect(!isOrange(connectiveColor))
				#expect(!isRed(literalColor))
				if appearance == .aqua
				{
					let base = try #require(color(
						in: storage,
						matching: "ordinary text"
					))
					#expect(isBlack(base))
					#expect(isBlack(connectiveColor))
				}
				if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
				{
					try AppTestPNGWriter.write(
						source,
						to: URL(fileURLWithPath: directory).appendingPathComponent(
							"source-reference-\(appearance.rawValue).png"
						)
					)
				}
				window.setContentSize(NSSize(
					width: 300,
					height: 300
				))
			}
			text.setSelectedRange(NSRange(
				location: storage.length,
				length: 0
			))
			text.insertText(
				"\n- added `new`",
				replacementRange: text.selectedRange()
			)
			#expect(text.string.hasSuffix("\n- added `new`"))
			#expect(isRed(try #require(color(
				in: storage,
				matching: "- added"
			))))
			#expect(isGreen(try #require(color(
				in: storage,
				matching: "`new`"
			))))
			let finalStyle = storage.attribute(
				.paragraphStyle,
				at: storage.length - 1,
				effectiveRange: nil
			) as? NSParagraphStyle
			#expect(finalStyle?.minimumLineHeight == 22)
			source.render(
				text: "",
				path: "blank.md",
				editable: true
			)
			text.insertText(
				"# New\n- row",
				replacementRange: NSRange(
					location: 0,
					length: 0
				)
			)
			#expect(isRed(try #require(color(
				in: storage,
				matching: "New"
			))))
			#expect(isRed(try #require(color(
				in: storage,
				matching: "- row"
			))))
			let blankStyle = storage.attribute(
				.paragraphStyle,
				at: storage.length - 1,
				effectiveRange: nil
			) as? NSParagraphStyle
			#expect(blankStyle?.minimumLineHeight == 22)
		}
	}

	@Test func readonlySourceRejectsEditingAndLineRevealUsesUTF16() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			let text = "😀\r\nsecond\r\n"
			source.render(
				text: text,
				path: "sample.txt",
				editable: false
			)
			source.reveal(line: 3)
			// The emoji is two UTF-16 units; each CRLF contributes two more.
			#expect(source.textView.selectedRange() == NSRange(
				location: 12,
				length: 0
			))
			source.textView.insertText(
				"extra",
				replacementRange: source.textView.selectedRange()
			)
			#expect(source.textView.string == text)
		}
	}

	@Test func readonlyInputDoesNotReachSiblingComposer() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			source.render(
				text: "locked",
				path: "locked.txt",
				editable: false
			)
			let composer = NSTextView(frame: NSRect(
				x: 0,
				y: 0,
				width: 200,
				height: 80
			))
			composer.string = "draft"
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 400,
					height: 300
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			defer
			{
				window.close()
			}
			let host = try #require(window.contentView)
			source.frame = NSRect(
				x: 0,
				y: 80,
				width: 400,
				height: 220
			)
			host.addSubview(source)
			host.addSubview(composer)
			#expect(window.makeFirstResponder(source.textView))
			let event = try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				characters: "z",
				charactersIgnoringModifiers: "z",
				isARepeat: false,
				keyCode: 6
			))
			window.firstResponder?.keyDown(with: event)
			#expect(source.textView.string == "locked")
			#expect(composer.string == "draft")
		}
	}

	@Test func gutterLabelsTrackNativeRowsAcrossFindBarAndScroll() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			let longLine = String(
				repeating: "wrapped text ",
				count: 40
			)
			let text = ([longLine] + (2 ... 80).map
			{
				"line \($0)"
			})
			.joined(separator: "\n")
			source.render(
				text: text,
				path: "rows.swift",
				editable: false
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 420,
					height: 260
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = source
			defer
			{
				window.close()
			}
			window.makeKeyAndOrderFront(nil)
			window.contentView?.layoutSubtreeIfNeeded()
			let scroll = try #require(source.subviews.first as? NSScrollView)
			let manager = try #require(source.textView.layoutManager)
			let firstGlyph = manager.glyphIndexForCharacter(at: 0)
			let lateGlyph = manager.glyphIndexForCharacter(at: 200)
			let firstRow = manager.lineFragmentRect(
				forGlyphAt: firstGlyph,
				effectiveRange: nil
			)
			let wrappedRow = manager.lineFragmentRect(
				forGlyphAt: lateGlyph,
				effectiveRange: nil
			)
			#expect(wrappedRow.minY > firstRow.minY)
			try requireGutterAlignment(
				source,
				line: 1,
				expectedOffset: 0,
				in: window
			)
			let show = NSMenuItem()
			show.tag = NSTextFinder.Action.showFindInterface.rawValue
			source.textView.performFindPanelAction(show)
			scroll.tile()
			window.contentView?.layoutSubtreeIfNeeded()
			#expect(scroll.isFindBarVisible)
			try requireGutterAlignment(
				source,
				line: 1,
				expectedOffset: 0,
				in: window
			)
			let targetOffset = (text as NSString).range(of: "line 40").location
			#expect(targetOffset != NSNotFound)
			source.reveal(line: 40)
			window.contentView?.layoutSubtreeIfNeeded()
			try requireGutterAlignment(
				source,
				line: 40,
				expectedOffset: targetOffset,
				in: window
			)
			try requireGutterInkClippedToContent(
				source,
				scroll: scroll
			)
			try requireNativeRulerInkClippedToContent(
				source,
				scroll: scroll
			)
			let hide = NSMenuItem()
			hide.tag = NSTextFinder.Action.hideFindInterface.rawValue
			source.textView.performFindPanelAction(hide)
			window.contentView?.layoutSubtreeIfNeeded()
			#expect(!scroll.isFindBarVisible)
			try requireGutterAlignment(
				source,
				line: 40,
				expectedOffset: targetOffset,
				in: window
			)
		}
	}

	@Test func wrappedSourceFitsVisibleClipAcrossResizeAndFind() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = FileSourceView()
			let text = "😀 " + String(
				repeating: "MW",
				count: 40
			)
				+ "\nsecond logical line\nthird logical line"
			source.render(
				text: text,
				path: "wrap.txt",
				editable: false
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 430,
					height: 340
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = source
			defer
			{
				window.close()
			}
			window.makeKeyAndOrderFront(nil)
			source.layoutSubtreeIfNeeded()
			let scroll = try #require(source.subviews.first as? NSScrollView)
			let wrappedScrollOriginX = scroll.contentView.bounds.minX
			let selection = NSRange(
				location: 2,
				length: 5
			)
			source.textView.setSelectedRange(selection)
			try requireWrappedGlyphsVisible(
				source,
				scroll: scroll
			)

			window.setContentSize(NSSize(
				width: 300,
				height: 340
			))
			source.layoutSubtreeIfNeeded()
			try requireWrappedGlyphsVisible(
				source,
				scroll: scroll
			)

			let show = NSMenuItem()
			show.tag = NSTextFinder.Action.showFindInterface.rawValue
			source.textView.performFindPanelAction(show)
			scroll.tile()
			source.layoutSubtreeIfNeeded()
			#expect(scroll.isFindBarVisible)
			try requireWrappedGlyphsVisible(
				source,
				scroll: scroll
			)

			let hide = NSMenuItem()
			hide.tag = NSTextFinder.Action.hideFindInterface.rawValue
			source.textView.performFindPanelAction(hide)
			scroll.tile()
			source.layoutSubtreeIfNeeded()
			#expect(!scroll.isFindBarVisible)
			try requireWrappedGlyphsVisible(
				source,
				scroll: scroll
			)

			source.setWrapsLines(false)
			source.layoutSubtreeIfNeeded()
			#expect(scroll.hasHorizontalScroller)
			#expect(source.textView.frame.width > scroll.contentView.bounds.width)
			#expect(source.textView.selectedRange() == selection)
			#expect(source.textView.string == text)
			scroll.contentView.scroll(to: NSPoint(
				x: 80,
				y: 0
			))
			scroll.reflectScrolledClipView(scroll.contentView)
			#expect(scroll.contentView.bounds.minX > 0)
			source.setWrapsLines(true)
			source.layoutSubtreeIfNeeded()
			#expect(abs(scroll.contentView.bounds.minX - wrappedScrollOriginX) < 1)
			try requireWrappedGlyphsVisible(
				source,
				scroll: scroll
			)
			#expect(source.textView.selectedRange() == selection)
			#expect(source.textView.string == text)
		}
	}

	private func requireWrappedGlyphsVisible(
		_ source: FileSourceView,
		scroll: NSScrollView
	) throws
	{
		let text = source.textView
		let manager = try #require(text.layoutManager)
		let container = try #require(text.textContainer)
		manager.ensureLayout(for: container)
		let visibleInText = text.convert(
			scroll.contentView.bounds,
			from: scroll.contentView
		)
		let inset = text.textContainerInset
		let visibleWidth = visibleInText.maxX - max(
			0,
			visibleInText.minX
		)
		#expect(abs(text.frame.width - visibleWidth) < 1)
		#expect(abs(container.containerSize.width
				- (visibleWidth - inset.width * 2)) < 1)
		var visualRows = 0
		var rightmostGlyph = CGFloat.zero
		manager.enumerateLineFragments(
			forGlyphRange: NSRange(
				location: 0,
				length: manager.numberOfGlyphs
			)
		)
		{
			_, _, _, glyphRange, _ in
			visualRows += 1
			let ink = manager.boundingRect(
				forGlyphRange: glyphRange,
				in: container
			)
			rightmostGlyph = max(
				rightmostGlyph,
				ink.maxX + text.textContainerOrigin.x
			)
		}
		#expect(visualRows > 3)
		#expect(rightmostGlyph <= visibleInText.maxX - 1)
		#expect(SourceLineIndex(text.string).lineStarts.count == 3)
		#expect(source.lineNumberBoundsInWindow(forLine: 3) != nil)
		#expect(source.lineNumberBoundsInWindow(forLine: 4) == nil)
	}

	private func requireGutterAlignment(
		_ source: FileSourceView,
		line: Int,
		expectedOffset: Int,
		in window: NSWindow
	) throws
	{
		let text = source.textView
		let manager = try #require(text.layoutManager)
		let glyph = manager.glyphIndexForCharacter(at: expectedOffset)
		let fragment = manager.lineFragmentRect(
			forGlyphAt: glyph,
			effectiveRange: nil
		)
		let textRect = fragment.offsetBy(
			dx: text.textContainerOrigin.x,
			dy: text.textContainerOrigin.y
		)
		let textRowInWindow = text.convert(
			textRect,
			to: nil
		)
		let labelInWindow = try #require(source.lineNumberBoundsInWindow(forLine: line))
		#expect(abs(labelInWindow.midY - textRowInWindow.midY) < 1)
		let scroll = try #require(source.subviews.first as? NSScrollView)
		let ruler = try #require(scroll.verticalRulerView)
		let labelInRuler = ruler.convert(
			labelInWindow,
			from: nil
		)
		#expect(ruler.bounds.intersects(labelInRuler))
		let clipBounds = ruler.convert(
			scroll.contentView.bounds,
			from: scroll.contentView
		)
		let contentViewport = NSRect(
			x: ruler.bounds.minX,
			y: clipBounds.minY,
			width: ruler.bounds.width,
			height: clipBounds.height
		).intersection(ruler.bounds)
		#expect(contentViewport.intersects(labelInRuler))
		#expect(text.window === window)
		let click = try #require(NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: NSPoint(
				x: labelInWindow.midX,
				y: labelInWindow.midY
			),
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		))
		ruler.mouseDown(with: click)
		#expect(text.selectedRange().location == expectedOffset)
	}

	private func requireGutterInkClippedToContent(
		_ source: FileSourceView,
		scroll: NSScrollView
	) throws
	{
		try requireRulerInkClippedToContent(
			source,
			scroll: scroll
		)
		{
			ruler, canvas in
			ruler.drawHashMarksAndLabels(in: canvas)
		}
	}

	private func requireNativeRulerInkClippedToContent(
		_ source: FileSourceView,
		scroll: NSScrollView
	) throws
	{
		try requireRulerInkClippedToContent(
			source,
			scroll: scroll
		)
		{
			ruler, canvas in
			ruler.draw(canvas)
		}
	}

	private func requireRulerInkClippedToContent(
		_ source: FileSourceView,
		scroll: NSScrollView,
		draw: (FileSourceLineRuler, NSRect) -> Void
	) throws
	{
		let ruler = try #require(scroll.verticalRulerView as? FileSourceLineRuler)
		let clipBounds = ruler.convert(
			scroll.contentView.bounds,
			from: scroll.contentView
		)
		let viewport = NSRect(
			x: ruler.bounds.minX,
			y: clipBounds.minY,
			width: ruler.bounds.width,
			height: clipBounds.height
		).intersection(ruler.bounds)
		let padding: CGFloat = 80
		let canvas = ruler.bounds.insetBy(
			dx: 0,
			dy: -padding
		)
		let offscreenLabel = (1 ... 80).contains
		{
			line in
			guard let windowBounds = source.lineNumberBoundsInWindow(forLine: line)
			else
			{
				return false
			}
			let bounds = ruler.convert(
				windowBounds,
				from: nil
			)
			let center = NSPoint(
				x: bounds.midX,
				y: bounds.midY
			)
			return canvas.contains(center) && !viewport.contains(center)
		}
		#expect(offscreenLabel)
		let ink = try captureCanvas(canvas: canvas)
		{
			draw(
				ruler,
				canvas
			)
		}
		let viewportMask = try captureCanvas(canvas: canvas)
		{
			NSColor.white.setFill()
			NSBezierPath(rect: viewport).fill()
		}
		var inside = 0
		var outside = 0
		var rightEdgeInk = 0
		for y in 0 ..< ink.pixelsHigh
		{
			for x in 0 ..< ink.pixelsWide
			{
				guard let color = ink.colorAt(
					x: x,
					y: y
				), color.alphaComponent > 0.01
				else
				{
					continue
				}
				let allowed = viewportMask.colorAt(
					x: x,
					y: y
				)?.alphaComponent ?? 0
				if allowed < 0.01
				{
					outside += 1
				}
				else
				{
					inside += 1
					if x >= ink.pixelsWide - 3
					{
						rightEdgeInk += 1
					}
				}
			}
		}
		#expect(inside > 0)
		#expect(outside == 0)
		#expect(rightEdgeInk == 0)
	}

	private func captureCanvas(
		canvas: NSRect,
		draw: () -> Void
	) throws -> NSBitmapImageRep
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(ceil(canvas.width)),
			pixelsHigh: Int(ceil(canvas.height)),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		let previous = NSGraphicsContext.current
		NSGraphicsContext.current = context
		defer
		{
			NSGraphicsContext.current = previous
		}
		context.cgContext.clear(CGRect(
			x: 0,
			y: 0,
			width: canvas.width,
			height: canvas.height
		))
		context.cgContext.translateBy(
			x: -canvas.minX,
			y: -canvas.minY
		)
		draw()
		context.flushGraphics()
		return bitmap
	}

	private func color(
		in storage: NSTextStorage,
		matching token: String
	) -> NSColor?
	{
		let range = (storage.string as NSString).range(of: token)
		guard range.location != NSNotFound
		else
		{
			return nil
		}
		return storage.attribute(
			.foregroundColor,
			at: range.location,
			effectiveRange: nil
		) as? NSColor
	}

	private func isRed(_ color: NSColor) -> Bool
	{
		let rgb = color.usingColorSpace(.sRGB) ?? color
		return rgb.redComponent > rgb.greenComponent * 1.5
			&& rgb.redComponent > rgb.blueComponent * 1.5
	}

	private func isGreen(_ color: NSColor) -> Bool
	{
		let rgb = color.usingColorSpace(.sRGB) ?? color
		return rgb.greenComponent > rgb.redComponent * 1.4
			&& rgb.greenComponent > rgb.blueComponent * 1.3
	}

	private func isOrange(_ color: NSColor) -> Bool
	{
		let rgb = color.usingColorSpace(.sRGB) ?? color
		return rgb.redComponent > rgb.greenComponent
			&& rgb.greenComponent > rgb.blueComponent
			&& rgb.redComponent > 0.7
	}

	private func isBlack(_ color: NSColor) -> Bool
	{
		let rgb = color.usingColorSpace(.sRGB) ?? color
		return max(
			rgb.redComponent,
			rgb.greenComponent,
			rgb.blueComponent
		) < 0.1
	}

}
