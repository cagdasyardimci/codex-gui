import AppKit

/// Selectable source with logical old/new line gutters outside the copied text.
@MainActor
final class GitUnifiedCodeView: NSView
{
	enum GutterMode: String
	{
		case unified, old, new
	}

	private let source: GitDiffTextView
	private let scroll = NSScrollView()
	private let rows: [GitDiffRow]
	private let path: String
	private let gutterMode: GutterMode
	private var measuredCodeWidth = GitCodeViewport.minimumDocumentWidth
	private var heightConstraint: NSLayoutConstraint?
	private var additionalVisualLines: [Int] = []
	private let unwrappedDocumentHeight: CGFloat
	private(set) var naturalContentHeight: CGFloat
	var visualLineCounts: [Int]
	{
		source.visualLineCounts
	}
	var visualRowRects: [NSRect]
	{
		source.visualRowRects
	}
	var hasHorizontalScroller: Bool
	{
		scroll.hasHorizontalScroller
	}
	var onContentHeightChange: (() -> Void)?
	var wrapsCode = false
	{
		didSet
		{
			guard oldValue != wrapsCode
			else
			{
				return
			}
			scroll.hasHorizontalScroller = !wrapsCode
			if wrapsCode
			{
				scroll.contentView.scroll(to: .zero)
				scroll.reflectScrolledClipView(scroll.contentView)
			}
			render()
			needsLayout = true
		}
	}
	private let font = NSFont.monospacedSystemFont(
		ofSize: 12,
		weight: .regular
	)
	static let lineHeight: CGFloat = 19

	static func contentHeight(rowCount: Int) -> CGFloat
	{
		CGFloat(rowCount) * lineHeight + 16
	}

	init(
		rows: [GitDiffRow],
		path: String,
		gutterMode: GutterMode = .unified,
		placeholderIndices: Set<Int> = []
	)
	{
		self.rows = rows
		self.path = path
		self.gutterMode = gutterMode
		let hardBreakCount = rows.reduce(0)
		{
			$0 + $1.text.unicodeScalars.filter(CharacterSet.newlines.contains).count
		}
		unwrappedDocumentHeight = CGFloat(rows.count + hardBreakCount) * Self.lineHeight + 2
		naturalContentHeight = Self.contentHeight(rowCount: rows.count)
		source = GitDiffTextView(frame: .zero)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.masksToBounds = true
		configureSourceText(placeholderIndices: placeholderIndices)
		let height = unwrappedDocumentHeight
		let longestSourceLineWidth = rows.map
		{
			($0.text as NSString).size(withAttributes: [.font: font]).width
		}
		.max() ?? 0
		measuredCodeWidth = max(
			GitCodeViewport.minimumDocumentWidth,
			longestSourceLineWidth + 30
		)
		source.frame = NSRect(
			x: 0,
			y: 0,
			width: measuredCodeWidth,
			height: height
		)
		installSourceScrollView()
		render()
	}

	private func configureSourceText(placeholderIndices: Set<Int>)
	{
		source.rows = rows
		source.placeholderIndices = placeholderIndices
		source.drawsRoundedChangeHighlights = gutterMode == .unified
		source.isEditable = false
		source.isSelectable = true
		source.isRichText = false
		source.isAutomaticLinkDetectionEnabled = false
		source.isAutomaticQuoteSubstitutionEnabled = false
		source.isAutomaticDashSubstitutionEnabled = false
		source.isAutomaticSpellingCorrectionEnabled = false
		source.isVerticallyResizable = false
		source.isHorizontallyResizable = false
		source.textContainerInset = NSSize(
			width: GitCodeViewport.textInset,
			height: 0
		)
		source.textContainer?.lineFragmentPadding = 0
		source.autoresizingMask = []
		source.textContainer?.widthTracksTextView = false
		source.textContainer?.heightTracksTextView = false
		source.textContainer?.containerSize = NSSize(
			width: GitCodeViewport.minimumDocumentWidth,
			height: 1
		)
		source.drawsBackground = false
		source.font = font
		switch gutterMode
		{
		case .unified:
			source.setAccessibilityLabel(
				"Read-only unified diff for \(path). Deleted rows show their old source "
					+ "line number; added rows show their new source line number."
			)
		case .old:
			source.setAccessibilityLabel("Read-only old side of split diff for \(path). "
				+ "Only old source line numbers appear in the gutter.")
		case .new:
			source.setAccessibilityLabel("Read-only new side of split diff for \(path). "
				+ "Only new source line numbers appear in the gutter.")
		}
	}

	private func installSourceScrollView()
	{
		scroll.documentView = source
		scroll.hasHorizontalScroller = true
		scroll.hasVerticalScroller = false
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		let ruler = GitDiffLineRuler(
			scrollView: scroll,
			source: source,
			rows: rows,
			font: font,
			gutterMode: gutterMode
		)
		scroll.verticalRulerView = ruler
		scroll.hasVerticalRuler = true
		scroll.rulersVisible = true
		AppKitLayout.pin(
			scroll,
			to: self,
			inset: 0
		)
		let heightConstraint = heightAnchor.constraint(equalToConstant: naturalContentHeight)
		heightConstraint.isActive = true
		self.heightConstraint = heightConstraint
	}

	func manageHeightFromParent()
	{
		heightConstraint?.isActive = false
	}

	func setAdditionalVisualLines(_ counts: [Int])
	{
		guard counts != additionalVisualLines
		else
		{
			return
		}
		additionalVisualLines = counts
		source.additionalVisualLines = counts
		render()
		needsLayout = true
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func layout()
	{
		super.layout()
		scroll.tile()
		if wrapsCode
		{
			layoutWrappedSource()
			return
		}
		layoutUnwrappedSource()
	}

	private func layoutWrappedSource()
	{
		let width = max(
			1,
			scroll.contentView.bounds.width
		)
		let containerSize = NSSize(
			width: max(
				1,
				width - 2 * GitCodeViewport.textInset
			),
			height: .greatestFiniteMagnitude
		)
		if source.textContainer?.containerSize != containerSize
		{
			source.textContainer?.containerSize = containerSize
		}
		if source.frame.width != width
		{
			source.setFrameSize(NSSize(
				width: width,
				height: source.frame.height
			))
		}
		if let container = source.textContainer, let manager = source.layoutManager
		{
			manager.ensureLayout(for: container)
			source.updateVisualRowRects()
			let usedHeight = ceil(max(
				manager.usedRect(for: container).maxY,
				source.visualRowRects.last?.maxY ?? 0
			)) + 2
			source.setFrameSize(NSSize(
				width: width,
				height: max(
					1,
					usedHeight
				)
			))
			scroll.verticalRulerView?.needsDisplay = true
			updateNaturalHeight(max(
				16,
				usedHeight + 14
			))
		}
	}

	private func layoutUnwrappedSource()
	{
		let additionalLineCount = additionalVisualLines.reduce(
			0,
			+
		)
		let additionalLineHeight = CGFloat(additionalLineCount) * Self.lineHeight
		let geometry = GitCodeViewport(
			viewportWidth: scroll.contentView.bounds.width,
			measuredCodeWidth: measuredCodeWidth,
			documentHeight: unwrappedDocumentHeight + additionalLineHeight
		)
		if source.textContainer?.containerSize != geometry.containerSize
		{
			source.textContainer?.containerSize = geometry.containerSize
		}
		if source.frame.size != geometry.documentSize
		{
			source.setFrameSize(geometry.documentSize)
		}
		source.updateVisualRowRects()
		if let container = source.textContainer, let manager = source.layoutManager
		{
			let usedHeight = ceil(max(
				manager.usedRect(for: container).maxY,
				source.visualRowRects.last?.maxY ?? 0
			)) + 2
			let documentHeight = max(
				geometry.documentSize.height,
				usedHeight
			)
			if source.frame.height != documentHeight
			{
				source.setFrameSize(NSSize(
					width: geometry.documentSize.width,
					height: documentHeight
				))
			}
			updateNaturalHeight(max(
				16,
				usedHeight + 14
			))
		}
		scroll.verticalRulerView?.needsDisplay = true
	}

	private func render()
	{
		let style = NSMutableParagraphStyle()
		style.minimumLineHeight = Self.lineHeight
		style.maximumLineHeight = Self.lineHeight
		style.lineBreakMode = wrapsCode ? .byCharWrapping : .byClipping
		style.tabStops = []
		style.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
		let text = rows.map(\.text).joined(separator: "\n")
		let attributed = NSMutableAttributedString(
			string: text,
			attributes: [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: style]
		)
		applySplitRowSpacing(
			to: attributed,
			paragraphStyle: style
		)
		applySyntaxColors(
			to: attributed,
			text: text
		)
		applyChangedRangeBackgrounds(to: attributed)

		let selection = source.selectedRange()
		source.textStorage?.setAttributedString(attributed)
		if NSMaxRange(selection) <= attributed.length
		{
			source.setSelectedRange(selection)
		}
	}

	private func applySplitRowSpacing(
		to attributed: NSMutableAttributedString,
		paragraphStyle: NSMutableParagraphStyle
	)
	{
		if !additionalVisualLines.isEmpty
		{
			var paragraphOffset = 0
			for (index, row) in rows.enumerated()
			{
				let length = (row.text as NSString).length
				if additionalVisualLines.indices.contains(index), additionalVisualLines[index] > 0
				{
					let finalParagraphStart = row.text.utf16.enumerated().reduce(0)
					{
						start, element in
						guard let scalar = UnicodeScalar(element.element),
								CharacterSet.newlines.contains(scalar)
						else
						{
							return start
						}
						return element.offset + 1
					}
					let paragraph = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
					paragraph.paragraphSpacing = CGFloat(additionalVisualLines[index])
						* Self.lineHeight
					attributed.addAttribute(
						.paragraphStyle,
						value: paragraph,
						range: NSRange(
							location: paragraphOffset + finalParagraphStart,
							length: length - finalParagraphStart
								+ (index + 1 < rows.count ? 1 : 0)
						)
					)
				}
				paragraphOffset += length + 1
			}
		}
	}

	private func applySyntaxColors(
		to attributed: NSMutableAttributedString,
		text: String
	)
	{
		let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let language = CodePreviewPresentation(
			text: text,
			relativePath: path
		).language
		if let highlighted = ConversationCodeHighlighter.highlightedCode(
			text,
			language: language,
			dark: dark
		)
		{
			highlighted.enumerateAttribute(
				.foregroundColor,
				in: NSRange(
					location: 0,
					length: highlighted.length
				)
			)
			{
				color, range, _ in
				if let color, NSMaxRange(range) <= attributed.length
				{
					attributed.addAttribute(
						.foregroundColor,
						value: color,
						range: range
					)
				}
			}
		}
	}

	private func applyChangedRangeBackgrounds(to attributed: NSMutableAttributedString)
	{
		var offset = 0
		for row in rows
		{
			let length = (row.text as NSString).length
			let color: NSColor? = row.kind == .addition ? .systemGreen : row
				.kind == .deletion ? .systemRed : nil
			if let color, !source.drawsRoundedChangeHighlights
			{
				for span in row.changedRanges where span.location >= 0 && NSMaxRange(span) <= length
				{
					attributed.addAttribute(
						.backgroundColor,
						value: color.withAlphaComponent(0.30),
						range: NSRange(
							location: offset + span.location,
							length: span.length
						)
					)
				}
			}
			offset += length + 1
		}
	}

	private func updateNaturalHeight(_ height: CGFloat)
	{
		guard naturalContentHeight != height
		else
		{
			return
		}
		naturalContentHeight = height
		heightConstraint?.constant = height
		onContentHeightChange?()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		render()
	}

}
