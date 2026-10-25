import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct FileDocumentViewTests
{

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

	@Test func switchingDocumentsRetainsIndependentSourceViews() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = FileDocumentViewController()
			var first = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "first.txt"
				),
				isRetained: true,
				content: .text("alpha")
			)
			var second = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "second.txt"
				),
				isRetained: true,
				content: .text("beta")
			)
			first.status = .ready
			second.status = .ready
			controller.onEdit =
			{
				id, text in
				if id == first.id
				{
					first.content = .text(text)
				}
			}
			controller.render(first)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 500,
					height: 350
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.contentView = controller.view
			defer
			{
				window.close()
			}
			let firstText = try #require(findText(in: controller.view))
			#expect(window.makeFirstResponder(firstText))
			firstText.insertText(
				"Z",
				replacementRange: NSRange(
					location: 0,
					length: 0
				)
			)
			#expect(firstText.string == "Zalpha")
			firstText.setSelectedRange(NSRange(
				location: 2,
				length: 0
			))
			controller.render(second)
			let secondText = try #require(findText(in: controller.view))
			#expect(firstText !== secondText)
			secondText.setSelectedRange(NSRange(
				location: 1,
				length: 0
			))
			controller.render(first)
			#expect(findText(in: controller.view) === firstText)
			#expect(firstText.string == "Zalpha")
			#expect(firstText.selectedRange().location == 2)
			#expect(secondText.selectedRange().location == 1)
			#expect(firstText.undoManager?.canUndo == true)
			firstText.undoManager?.undo()
			#expect(firstText.string == "alpha")
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
			window.prepareForTesting()
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

	@Test func openMenuUsesInstalledDestinationsAndCapturedFile() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = FileDocumentViewController()
			controller.showsHeader = false
			let icon = NSImage(size: NSSize(
				width: 16,
				height: 16
			))
			let names = ["VS Code", "Zed", "Terminal", "Kitty", "Xcode"]
			let destinations = names.map
			{
				FileOpeningDestination(
					title: $0,
					application: URL(fileURLWithPath: "/Applications/\($0).app"),
					opensFolder: $0 == "Terminal" || $0 == "Kitty",
					icon: icon
				)
			}
			controller.openingDestinations =
			{
				destinations
			}
			var opened: [FileLocation] = []
			controller.openDefaultApplication =
			{
				opened.append($0)
			}
			var first = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "first.md"
				),
				isRetained: true,
				content: .text("# First")
			)
			first.status = .ready
			controller.render(first)
			let menu = controller.makeOpenMenu()
			#expect(menu.items.map(\.title) == [
				"VS Code",
				"Zed",
				"Default app",
				"Terminal",
				"Kitty",
				"Xcode",
				"",
				"Open in folder",
				"Open in GitHub",
				"Save as…"
			])
			#expect(menu.items.prefix(2).allSatisfy
			{
				$0.image != nil
			})
			#expect(menu.items[3].image != nil)
			#expect(menu.items[4].image != nil)
			#expect(menu.items[5].image != nil)
			var second = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "second.txt"
				),
				isRetained: true,
				content: .text("Second")
			)
			second.status = .ready
			controller.render(second)
			let defaultItem = try #require(menu.items.first
			{
				$0.title == "Default app"
			})
			#expect(NSApp.sendAction(
				try #require(defaultItem.action),
				to: defaultItem.target,
				from: defaultItem
			))
			#expect(opened == [first.location])
		}
	}

	@Test func copyMarkdownButtonUsesVisibleBufferAndDocumentChrome() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = FileDocumentViewController()
			controller.showsHeader = false
			var document = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "notes.md"
				),
				isRetained: true,
				content: .text("# Initial")
			)
			document.status = .ready
			controller.render(document)
			let copy = try #require(findButton(
				"Copy Markdown",
				in: controller.view
			))
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 500,
					height: 350
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.contentView = controller.view
			defer
			{
				window.close()
			}
			#expect(!copy.isHidden)
			controller.setSourceVisible(true)
			let source = try #require(findText(in: controller.view))
			let scroll = try #require(findSourceScroll(in: controller.view))
			controller.view.layoutSubtreeIfNeeded()
			let buttonRect = copy.convert(
				copy.bounds,
				to: controller.view
			)
			let sourceRect = scroll.convert(
				scroll.bounds,
				to: controller.view
			)
			#expect(buttonRect.minX >= sourceRect.maxX + 4)
			#expect(sourceRect.maxY >= controller.view.bounds.maxY - 1)
			#expect(buttonRect.maxY >= sourceRect.maxY - 8)
			window.setContentSize(NSSize(
				width: 260,
				height: 280
			))
			window.appearance = NSAppearance(named: .darkAqua)
			controller.view.layoutSubtreeIfNeeded()
			try requireCopyAccessoryBackgroundMatchesDocument(controller.view)
			if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
			{
				try AppTestPNGWriter.write(
					controller.view,
					to: URL(fileURLWithPath: directory)
						.appendingPathComponent("copy-source-dark.png")
				)
			}
			let narrowButton = copy.convert(
				copy.bounds,
				to: controller.view
			)
			let narrowSource = scroll.convert(
				scroll.bounds,
				to: controller.view
			)
			#expect(narrowButton.minX >= narrowSource.maxX + 4)
			#expect(narrowSource.maxY >= controller.view.bounds.maxY - 1)
			window.appearance = NSAppearance(named: .aqua)
			controller.view.layoutSubtreeIfNeeded()
			try requireCopyAccessoryBackgroundMatchesDocument(controller.view)
			if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
			{
				try AppTestPNGWriter.write(
					controller.view,
					to: URL(fileURLWithPath: directory)
						.appendingPathComponent("copy-source-light.png")
				)
			}
			#expect(!copy.isHidden)
			source.string = "# Edited\r\n"
			let selected = NSRange(
				location: 2,
				length: 3
			)
			source.setSelectedRange(selected)
			#expect(NSApp.sendAction(
				try #require(copy.action),
				to: copy.target,
				from: copy
			))
			#expect(NSPasteboard.general.string(forType: .string) == "# Edited\r\n")
			#expect(source.selectedRange() == selected)
			document.content = .text("# Edited\r\n")
			controller.render(document)
			controller.setSourceVisible(false)
			#expect(!copy.isHidden)
			#expect(NSApp.sendAction(
				try #require(copy.action),
				to: copy.target,
				from: copy
			))
			#expect(NSPasteboard.general.string(forType: .string) == "# Edited\r\n")
			var other = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "other.txt"
				),
				isRetained: true,
				content: .text("Other")
			)
			other.status = .ready
			controller.render(other)
			#expect(copy.superview?.isHidden == true)
			document.isReadOnly = true
			controller.render(document)
			#expect(!copy.isHidden)
			#expect(NSApp.sendAction(
				try #require(copy.action),
				to: copy.target,
				from: copy
			))
			#expect(NSPasteboard.general.string(forType: .string) == "# Edited\r\n")
			document.content = .empty
			controller.render(document)
			#expect(copy.isHidden || copy.superview?.isHidden == true)
		}
	}

	@Test func metadataInitialInsertionAndResizeSettleInsideFilesContainer() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let files = FilesViewController()
			files.loadViewIfNeeded()
			let description = "Standard Markdown, GitHub-flavored Markdown, " +
				"common extensions, and Mermaid diagrams"
			let source = "---\ntitle: Markdown rendering benchmark\ndescription: " + description +
				"\ntags: [markdown, benchmark, rendering, mermaid]\n---\n\n# Body\n\n" +
				String(
					repeating: "A paragraph.\n\n",
					count: 30
				)
			var document = FileViewerDocument(
				id: UUID(),
				location: FileLocation(
					root: "/tmp",
					relativePath: "metadata.md"
				),
				isRetained: true,
				content: .text(source)
			)
			document.status = .ready
			files.document.render(document)
			let preview = try #require(findPreview(in: files.document.view))
			await preview.waitForLoading()
			await files.document.waitForMetadataLayout()
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 1200,
					height: 700
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			window.contentViewController = files
			let metadata = try #require(findMetadata(in: files.document.view))
			let scroll = try #require(metadata.enclosingScrollView)
			var heights: [CGFloat] = []
			for width in [CGFloat(1200), 800, 1200]
			{
				window.setContentSize(NSSize(
					width: width,
					height: 700
				))
				files.view.layoutSubtreeIfNeeded()
				await files.document.waitForMetadataLayout()
				let expectedHeight = metadata.height(forWidth: scroll.contentView.bounds.width)
				let expectedViewport = min(
					expectedHeight,
					files.document.view.bounds.height *
						LayoutTokens.FileMarkdown
						.maximumMetadataHeightFraction
				)
				#expect(abs(metadata.frame.width - scroll.contentView.bounds.width) < 1)
				#expect(abs(metadata.frame.height - expectedHeight) < 1)
				#expect(
					abs(scroll.contentView.bounds.height - expectedViewport) < 1,
					Comment(rawValue: "width=\(width) expected=\(expectedViewport) " +
						"metadata=\(metadata.frame) holder=\(scroll.superview!.frame) " +
						"scroll=\(scroll.frame) clip=\(scroll.contentView.frame) " +
						"clipbounds=\(scroll.contentView.bounds) " +
						"insets=\(scroll.contentInsets) " +
						"auto=\(scroll.automaticallyAdjustsContentInsets) " +
						"horizontal=\(scroll.hasHorizontalScroller) " +
						"vertical=\(scroll.hasVerticalScroller)")
				)
				let viewport = scroll.convert(
					scroll.bounds,
					to: files.document.view
				)
				#expect(viewport.minY >= files.document.view.bounds.minY)
				#expect(viewport.maxY <= files.document.view.bounds.maxY)
				#expect(scroll.contentView.bounds.origin == .zero)
				heights.append(metadata.frame.height)
			}
			#expect(heights[1] > heights[0])
			#expect(heights[2] == heights[0])
		}
	}

	private func findMetadata(in view: NSView) -> MarkdownFileMetadataView?
	{
		if let metadata = view as? MarkdownFileMetadataView
		{
			return metadata
		}
		return view.subviews.lazy.compactMap
		{
			findMetadata(in: $0)
		}.first
	}

	private func findPreview(in view: NSView) -> RichFilePreviewView?
	{
		if let preview = view as? RichFilePreviewView
		{
			return preview
		}
		for child in view.subviews
		{
			if let found = findPreview(in: child)
			{
				return found
			}
		}
		return nil
	}

	private func findMarkdownText(in view: NSView) -> MarkdownTextView?
	{
		if let text = view as? MarkdownTextView
		{
			return text
		}
		for child in view.subviews
		{
			if let found = findMarkdownText(in: child)
			{
				return found
			}
		}
		return nil
	}

	private func findPreviewScroll(in view: NSView) -> NSScrollView?
	{
		if let scroll = view as? NSScrollView,
			scroll.documentView is RichFilePreviewView
		{
			return scroll
		}
		for child in view.subviews
		{
			if let found = findPreviewScroll(in: child)
			{
				return found
			}
		}
		return nil
	}

	private func findButton(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.toolTip == label || button.title == label
		{
			return button
		}
		for child in view.subviews
		{
			if let found = findButton(
				label,
				in: child
			)
			{
				return found
			}
		}
		return nil
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

	private func requireCopyAccessoryBackgroundMatchesDocument(_ view: NSView) throws
	{
		let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: bitmap
		)
		let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
		let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
		let blankX = min(
			160,
			view.bounds.width - 80
		)
		let accessoryX = view.bounds.width - 20
		for y in [CGFloat(34), view.bounds.height - 34]
		{
			let blank = try #require(bitmap.colorAt(
				x: Int(blankX * scaleX),
				y: Int(y * scaleY)
			)?.usingColorSpace(.sRGB))
			let accessory = try #require(bitmap.colorAt(
				x: Int(accessoryX * scaleX),
				y: Int(y * scaleY)
			)?.usingColorSpace(.sRGB))
			#expect(abs(blank.redComponent - accessory.redComponent) < 0.02)
			#expect(abs(blank.greenComponent - accessory.greenComponent) < 0.02)
			#expect(abs(blank.blueComponent - accessory.blueComponent) < 0.02)
		}
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

	private func findText(in view: NSView) -> FileSourceTextView?
	{
		if let source = view as? FileSourceTextView
		{
			return source
		}
		for child in view.subviews
		{
			if let found = findText(in: child)
			{
				return found
			}
		}
		return nil
	}

	private func findSourceScroll(in view: NSView) -> NSScrollView?
	{
		if let scroll = view as? NSScrollView,
			scroll.documentView is FileSourceTextView
		{
			return scroll
		}
		for child in view.subviews
		{
			if let found = findSourceScroll(in: child)
			{
				return found
			}
		}
		return nil
	}

	private func findSearchField(in view: NSView) -> NSSearchField?
	{
		if let field = view as? NSSearchField
		{
			return field
		}
		for child in view.subviews
		{
			if let found = findSearchField(in: child)
			{
				return found
			}
		}
		return nil
	}
}
