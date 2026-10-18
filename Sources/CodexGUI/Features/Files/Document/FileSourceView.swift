import AppKit

@MainActor
final class FileSourceTextView: SourceTextView
{
	private let sourceUndoManager = UndoManager()

	override var undoManager: UndoManager?
	{
		sourceUndoManager
	}

}

struct FileSourceReadingState
{
	var selection: NSRange
	var scrollOrigin: NSPoint
}

@MainActor
final class FileSourceView: NSView, NSTextViewDelegate
{
	var onEdit: ((String) -> Void)?
	private(set) var textView: FileSourceTextView
	private let scrollView = NSScrollView()
	private let ruler: FileSourceLineRuler
	private var path = ""
	private var isUpdating = false
	private var wrapsLines = true
	private var needsTextSizing = true
	private var sizedViewportWidth: CGFloat = 0

	init()
	{
		let storage = NSTextStorage()
		let manager = NSLayoutManager()
		let container = NSTextContainer(size: NSSize(
			width: 0,
			height: CGFloat.greatestFiniteMagnitude
		))
		storage.addLayoutManager(manager)
		manager.addTextContainer(container)
		textView = FileSourceTextView(
			frame: .zero,
			textContainer: container
		)
		ruler = FileSourceLineRuler(scrollView: scrollView)
		super.init(frame: .zero)

		textView.delegate = self
		SourceTextViewport.configure(
			textView,
			wrapsLines: true
		)
		textView.allowsUndo = true
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.textContainerInset = NSSize(
			width: 9,
			height: 12
		)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		SourceTextViewport.install(
			textView,
			in: scrollView,
			ruler: ruler
		)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(scrolled),
			name: NSView.boundsDidChangeNotification,
			object: scrollView.contentView
		)
		scrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(scrolled),
			name: NSView.frameDidChangeNotification,
			object: scrollView.contentView
		)
		scrollView.contentView.postsFrameChangedNotifications = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	deinit
	{
		NotificationCenter.default.removeObserver(self)
	}

	func render(
		text: String,
		path: String,
		editable: Bool
	)
	{
		self.path = path
		if Data(textView.string.utf8) != Data(text.utf8)
		{
			isUpdating = true
			textView.string = text
			textView.undoManager?.removeAllActions()
			isUpdating = false
			needsTextSizing = true
		}
		textView.isEditable = editable
		textView.isSelectable = true
		refreshAppearance()
		ruler.update(text: text)
		needsLayout = true
	}

	func setWrapsLines(_ wraps: Bool)
	{
		guard wrapsLines != wraps
		else
		{
			return
		}
		wrapsLines = wraps
		needsTextSizing = true
		textView.isHorizontallyResizable = !wraps
		textView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		SourceTextViewport.setWrapping(
			wraps,
			for: textView,
			in: scrollView
		)
		textView.refreshSourceAppearance(
			appearance: effectiveAppearance,
			wrapsLines: wraps
		)
		applySyntaxColors()
		textView.layoutManager?.invalidateLayout(
			forCharacterRange: NSRange(
				location: 0,
				length: (textView.string as NSString).length
			),
			actualCharacterRange: nil
		)
		ruler.needsDisplay = true
		needsLayout = true
	}

	override func layout()
	{
		super.layout()
		scrollView.tile()
		let width = visibleTextWidth()
		guard needsTextSizing || abs(width - sizedViewportWidth) > 0.5
		else
		{
			return
		}
		needsTextSizing = false
		sizedViewportWidth = width
		guard let manager = textView.layoutManager,
				let container = textView.textContainer
		else
		{
			return
		}
		let inset = textView.textContainerInset
		if wrapsLines
		{
			SourceTextViewport.sizeWrappedText(
				textView,
				to: width
			)
			textView.setFrameSize(NSSize(
				width: width,
				height: max(
					textView.frame.height,
					scrollView.contentView.bounds.height
				)
			))
		}
		else
		{
			container.containerSize = NSSize(
				width: CGFloat.greatestFiniteMagnitude,
				height: CGFloat.greatestFiniteMagnitude
			)
		}
		// Programmatic source replacement does not grow the scroll view's document frame.
		manager.ensureLayout(for: container)
		let used = manager.usedRect(for: container)
		textView.setFrameSize(NSSize(
			width: wrapsLines ? width : max(
				width,
				ceil(used.maxX + inset.width * 2)
			),
			height: max(
				scrollView.contentView.bounds.height,
				ceil(used.maxY + inset.height * 2)
			)
		))
		ruler.needsDisplay = true
	}

	func captureReadingState() -> FileSourceReadingState
	{
		FileSourceReadingState(
			selection: textView.selectedRange(),
			scrollOrigin: scrollView.contentView.bounds.origin
		)
	}

	func restoreReadingState(_ state: FileSourceReadingState)
	{
		let length = (textView.string as NSString).length
		let start = min(
			max(
				0,
				state.selection.location
			),
			length
		)
		textView.setSelectedRange(NSRange(
			location: start,
			length: min(
				state.selection.length,
				length - start
			)
		))
		scrollView.contentView.scroll(to: state.scrollOrigin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	func reveal(line: Int)
	{
		layoutSubtreeIfNeeded()
		let index = SourceLineIndex(textView.string)
		let offset = index.lineStarts[min(
			max(
				1,
				line
			),
			index.lineStarts.count
		) - 1]
		textView.setSelectedRange(NSRange(
			location: offset,
			length: 0
		))
		textView.scrollRangeToVisible(NSRange(
			location: offset,
			length: 0
		))
	}

	/// Returns the same native gutter bounds used for drawing, in window coordinates.
	func lineNumberBoundsInWindow(forLine line: Int) -> NSRect?
	{
		guard let bounds = ruler.labelBounds(forLine: line)
		else
		{
			return nil
		}
		return ruler.convert(
			bounds,
			to: nil
		)
	}

	func textDidChange(_ notification: Notification)
	{
		guard !isUpdating
		else
		{
			return
		}
		ruler.update(text: textView.string)
		needsTextSizing = true
		needsLayout = true
		onEdit?(textView.string)
		applySyntaxColors()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshAppearance()
	}

	private func refreshAppearance()
	{
		scrollView.backgroundColor = .textBackgroundColor
		textView.refreshSourceAppearance(
			appearance: effectiveAppearance,
			wrapsLines: wrapsLines
		)
		ruler.needsDisplay = true
		applySyntaxColors()
	}

	private func applySyntaxColors()
	{
		guard let storage = textView.textStorage, storage.length > 0
		else
		{
			return
		}
		storage.beginEditing()
		SourceTextView.applySourceStyle(
			to: storage,
			text: textView.string,
			path: path,
			appearance: effectiveAppearance,
			wrapsLines: wrapsLines
		)
		storage.endEditing()
	}

	private func visibleTextWidth() -> CGFloat
	{
		// The converted clip edge excludes the vertical ruler's width.
		let visibleInText = textView.convert(
			scrollView.contentView.bounds,
			from: scrollView.contentView
		)
		return max(
			1,
			visibleInText.maxX - max(
				0,
				visibleInText.minX
			)
		)
	}

	@objc private func scrolled()
	{
		ruler.needsDisplay = true
		if abs(visibleTextWidth() - sizedViewportWidth) > 0.5
		{
			needsTextSizing = true
			needsLayout = true
		}
	}
}

@MainActor
final class FileSourceLineRuler: NSRulerView
{
	private var lines = SourceLineIndex("")
	private var labelAttributes: [NSAttributedString.Key: Any]
	{
		[
			.font: AppKitFontResolver.font(TypographyTokens.Transcript.codeHeader),
			.foregroundColor: NSColor.secondaryLabelColor
		]
	}

	init(scrollView: NSScrollView)
	{
		super.init(
			scrollView: scrollView,
			orientation: .verticalRuler
		)
		ruleThickness = 32
	}

	required init(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	func update(text: String)
	{
		lines = SourceLineIndex(text)
		needsDisplay = true
	}

	func labelBounds(forLine line: Int) -> NSRect?
	{
		guard lines.lineStarts.indices.contains(line - 1),
				let text = scrollView?.documentView as? NSTextView,
				let manager = text.layoutManager,
				let container = text.textContainer
		else
		{
			return nil
		}
		let offset = lines.lineStarts[line - 1]
		let fragment: NSRect
		if offset == text.textStorage?.length
		{
			let used = manager.usedRect(for: container)
			let font = text.font ?? AppKitFontResolver.font(TypographyTokens.Transcript.code)
			fragment = NSRect(
				x: 0,
				y: used.maxY,
				width: 0,
				height: max(
					manager.defaultLineHeight(for: font),
					text.defaultParagraphStyle?.minimumLineHeight ?? 0
				)
			)
		}
		else
		{
			let glyph = manager.glyphIndexForCharacter(at: offset)
			fragment = manager.lineFragmentRect(
				forGlyphAt: glyph,
				effectiveRange: nil
			)
		}
		let origin = text.textContainerOrigin
		let rowInText = fragment.offsetBy(
			dx: origin.x,
			dy: origin.y
		)
		let rowInRuler = convert(
			rowInText,
			from: text
		)
		let label = "\(line)" as NSString
		let size = label.size(withAttributes: labelAttributes)
		return NSRect(
			x: ruleThickness - size.width - 9,
			y: rowInRuler.midY - size.height / 2,
			width: size.width,
			height: size.height
		)
	}

	private func contentViewport() -> NSRect?
	{
		guard let contentView = scrollView?.contentView
		else
		{
			return nil
		}
		let converted = convert(
			contentView.bounds,
			from: contentView
		)
		return NSRect(
			x: bounds.minX,
			y: converted.minY,
			width: bounds.width,
			height: converted.height
		).intersection(bounds)
	}

	override func draw(_ dirtyRect: NSRect)
	{
		guard let viewport = contentViewport(),
				viewport.intersects(dirtyRect)
		else
		{
			return
		}
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: viewport).addClip()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		drawHashMarksAndLabels(in: dirtyRect.intersection(viewport))
	}

	override func mouseDown(with event: NSEvent)
	{
		guard let viewport = contentViewport(),
				viewport.contains(convert(
				event.locationInWindow,
				from: nil
				))
		else
		{
			return
		}
		guard let text = scrollView?.documentView as? NSTextView,
				let manager = text.layoutManager,
				let container = text.textContainer
		else
		{
			return
		}
		let textPoint = text.convert(
			event.locationInWindow,
			from: nil
		)
		let containerPoint = NSPoint(
			x: max(
				0,
				textPoint.x - text.textContainerOrigin.x
			),
			y: max(
				0,
				textPoint.y - text.textContainerOrigin.y
			)
		)
		let offset: Int
		if containerPoint.y >= manager.usedRect(for: container).maxY
		{
			offset = lines.utf16Length
		}
		else
		{
			let glyph = manager.glyphIndex(
				for: containerPoint,
				in: container
			)
			offset = manager.characterIndexForGlyph(at: glyph)
		}
		let line = lines.lineNumber(atUTF16Offset: offset) - 1
		let start = lines.lineStarts[line]
		let end = line + 1 < lines.lineStarts.count
			? lines.lineStarts[line + 1] : lines.utf16Length
		text.setSelectedRange(NSRange(
			location: start,
			length: end - start
		))
		text.window?.makeFirstResponder(text)
	}

	override func drawHashMarksAndLabels(in rect: NSRect)
	{
		guard let viewport = contentViewport(),
				viewport.intersects(rect)
		else
		{
			return
		}
		guard let text = scrollView?.documentView as? NSTextView,
				let manager = text.layoutManager,
				let container = text.textContainer
		else
		{
			return
		}
		let visible = scrollView?.contentView.bounds ?? .zero
		let firstLine: Int
		let finalLine: Int
		if manager.numberOfGlyphs > 0
		{
			func line(atY y: CGFloat) -> Int
			{
				let glyph = manager.glyphIndex(
					for: NSPoint(
						x: 0,
						y: max(
							0,
							y - text.textContainerOrigin.y
						)
					),
					in: container
				)
				let boundedGlyph = min(
					glyph,
					manager.numberOfGlyphs - 1
				)
				return lines.lineNumber(atUTF16Offset:
					manager.characterIndexForGlyph(at: boundedGlyph)) - 1
			}
			firstLine = max(
				0,
				line(atY: visible.minY) - 1
			)
			finalLine = min(
				lines.lineStarts.count - 1,
				line(atY: visible.maxY) + 1
			)
		}
		else
		{
			firstLine = 0
			finalLine = 0
		}
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: viewport).addClip()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		for index in firstLine ... finalLine
		{
			let line = index + 1
			guard let labelRect = labelBounds(forLine: line),
					labelRect.intersects(rect),
					labelRect.intersects(viewport)
			else
			{
				continue
			}
			("\(line)" as NSString).draw(
				at: labelRect.origin,
				withAttributes: labelAttributes
			)
		}
	}
}
