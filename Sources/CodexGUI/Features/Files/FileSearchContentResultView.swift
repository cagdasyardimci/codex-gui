import AppKit

@MainActor
final class FileSearchContentResultView: NSView
{
	let snippetLabel = FileSearchTextField(labelWithString: "")
	let locationLabel = FileSearchTextField(labelWithString: "")
	private let sourceLine: String
	private let query: String
	private var displayedLine: String
	private var displayedWidth: CGFloat = 0
	private var selected = false

	init(
		result: FileViewerSearchResult,
		query: String
	)
	{
		sourceLine = result.lineText
		displayedLine = Self.displayedSnippet(
			result.lineText,
			query: query,
			availableWidth: 150
		)
		self.query = query
		super.init(frame: .zero)
		let path = result.location.relativePath as NSString
		let filename = path.lastPathComponent
		let location = "\(filename):\(result.lineNumber)"

		snippetLabel.lineBreakMode = .byTruncatingTail
		snippetLabel.maximumNumberOfLines = 1
		snippetLabel.cell?.usesSingleLineMode = true
		snippetLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		snippetLabel.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		locationLabel.stringValue = location
		locationLabel.font = AppKitFontResolver.font(TypographyTokens.FileSearch.location)
		locationLabel.lineBreakMode = .byTruncatingMiddle
		locationLabel.maximumNumberOfLines = 1
		locationLabel.toolTip = "\(result.location.relativePath):\(result.lineNumber)"
		locationLabel.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
		locationLabel.setContentHuggingPriority(
			.defaultHigh,
			for: .horizontal
		)
		for label in [snippetLabel, locationLabel]
		{
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)
		}
		NSLayoutConstraint.activate([
			snippetLabel.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			snippetLabel.trailingAnchor.constraint(
				equalTo: locationLabel.leadingAnchor,
				constant: -10
			),
			snippetLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			locationLabel.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			locationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			snippetLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
			locationLabel.widthAnchor.constraint(
				lessThanOrEqualTo: widthAnchor,
				multiplier: 0.42
			),
			locationLabel.widthAnchor.constraint(
				lessThanOrEqualToConstant: LayoutTokens.FileSearch.locationMaximumWidth
			),
		])
		refreshSnippet()
		setAccessibilityLabel(
			"\(result.lineText), \(result.location.relativePath):\(result.lineNumber)"
		)
		toolTip = "\(result.lineText) — \(result.location.relativePath):\(result.lineNumber)"
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshSnippet()
	}

	override func layout()
	{
		super.layout()
		let width = snippetLabel.bounds.width
		guard width > 0, abs(width - displayedWidth) > 0.5
		else
		{
			return
		}
		displayedWidth = width
		let next = Self.displayedSnippet(
			sourceLine,
			query: query,
			availableWidth: width
		)
		guard next != displayedLine
		else
		{
			return
		}
		displayedLine = next
		refreshSnippet()
	}

	func setSelected(_ selected: Bool)
	{
		guard self.selected != selected
		else
		{
			return
		}
		self.selected = selected
		refreshSnippet()
	}

	private func refreshSnippet()
	{
		snippetLabel.attributedStringValue = highlightedSnippet()
		locationLabel.textColor = selected
			? AppKitColorTokens.fileSearchSelectedLocation : AppKitColorTokens.fileSearchLocation
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	static func displayedSnippet(
		_ text: String,
		query: String,
		availableWidth: CGFloat
	) -> String
	{
		let font = AppKitFontResolver.font(TypographyTokens.FileSearch.source)
		let prefix = text.prefix(256)
		if prefix.endIndex == text.endIndex,
			String(prefix).size(withAttributes: [.font: font]).width <= availableWidth
		{
			return text
		}
		guard !query.isEmpty
		else
		{
			return clippedPrefix(text)
		}
		let source = text as NSString
		let match = source.range(
			of: query,
			options: [.caseInsensitive, .literal]
		)
		guard let range = Range(
			match,
			in: text
		)
		else
		{
			return clippedPrefix(text)
		}
		let context = text[..<range.lowerBound].suffix(32)
		var before = String(context)
		let budget = availableWidth / 3
		var leading = context.startIndex == text.startIndex ? "" : "…"
		while !before.isEmpty,
				(leading + before).size(withAttributes: [.font: font]).width > budget
		{
			before.removeFirst()
			leading = "…"
		}
		if (leading + before).size(withAttributes: [.font: font]).width > budget
		{
			leading = ""
		}
		let after = text[range.lowerBound...].prefix(224)
		let trailing = after.endIndex == text.endIndex ? "" : "…"
		return leading + before + String(after) + trailing
	}

	private static func clippedPrefix(_ text: String) -> String
	{
		let prefix = text.prefix(256)
		return String(prefix) + (prefix.endIndex == text.endIndex ? "" : "…")
	}

	private func highlightedSnippet() -> NSAttributedString
	{
		let foreground = selected ? AppKitColorTokens.primaryText : AppKitColorTokens
			.fileSearchSnippet
		let text = displayedLine
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let value = NSMutableAttributedString(
			string: text,
			attributes: [
				.font: AppKitFontResolver.font(TypographyTokens.FileSearch.source),
				.paragraphStyle: paragraph,
				.foregroundColor: NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
					foreground,
					for: self
				)) ?? foreground,
			]
		)
		guard !query.isEmpty
		else
		{
			return value
		}
		let background = NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.fileSearchMatch,
			for: self
		)) ?? AppKitColorTokens.fileSearchMatch
		let source = text as NSString
		var start = 0
		while start < source.length
		{
			let found = source.range(
				of: query,
				options: [.caseInsensitive, .literal],
				range: NSRange(
					location: start,
					length: source.length - start
				)
			)
			guard found.location != NSNotFound, found.length > 0
			else
			{
				break
			}
			value.addAttribute(
				.backgroundColor,
				value: background,
				range: found
			)
			start = NSMaxRange(found)
		}
		return value
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}
}

@MainActor
final class FileSearchResultSelectionRow: NSTableRowView
{
	override func drawSelection(in dirtyRect: NSRect)
	{
		guard isSelected
		else
		{
			return
		}
		AppKitColorTokens.fileSearchSelection.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: ShapeTokens.FileSearch.selectionRadius,
			yRadius: ShapeTokens.FileSearch.selectionRadius
		).fill()
	}
}
