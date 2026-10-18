import AppKit

@MainActor
final class FileSearchContentResultView: NSView
{
	let snippetLabel = NSTextField(labelWithString: "")
	let locationLabel = NSTextField(labelWithString: "")
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

		snippetLabel.attributedStringValue = Self.highlightedSnippet(
			displayedLine,
			query: query
		)
		snippetLabel.lineBreakMode = .byTruncatingTail
		snippetLabel.maximumNumberOfLines = 1
		snippetLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		snippetLabel.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		locationLabel.stringValue = location
		locationLabel.font = .systemFont(ofSize: 12)
		locationLabel.textColor = .secondaryLabelColor
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
				constant: 3
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
		])
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
		let value = NSMutableAttributedString(attributedString: Self.highlightedSnippet(
			displayedLine,
			query: query
		))
		if selected
		{
			value.addAttribute(
				.foregroundColor,
				value: NSColor.labelColor,
				range: NSRange(
					location: 0,
					length: value.length
				)
			)
		}
		snippetLabel.attributedStringValue = value
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
		let font = NSFont.monospacedSystemFont(
			ofSize: 13,
			weight: .regular
		)
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

	static func highlightedSnippet(
		_ text: String,
		query: String
	) -> NSAttributedString
	{
		let value = NSMutableAttributedString(
			string: text,
			attributes: [
				.font: NSFont.monospacedSystemFont(
					ofSize: 13,
					weight: .regular
				),
				.foregroundColor: NSColor.secondaryLabelColor,
			]
		)
		guard !query.isEmpty
		else
		{
			return value
		}
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
				value: NSColor.systemBlue.withAlphaComponent(0.10),
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
		NSColor.labelColor.withAlphaComponent(0.06).setFill()
		NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: 8,
			yRadius: 8
		).fill()
	}
}
