import AppKit

/// Search-result variants own their typography, content layout, truncation and accessibility.
@MainActor
class DesktopSearchResultContentView: NSView
{
	enum Presentation
	{
		case chat(
			title: String,
			context: String,
			shortcut: String
		)
		case inlineFile(
			title: String,
			directory: String,
			shortcut: String
		)
		case inlineCommand(
			title: String,
			detail: String,
			leadingAccessory: NSView,
			suffix: String,
			opensPicker: Bool,
			enabled: Bool
		)
		case filename(path: String)
		case command(
			title: String,
			detail: String,
			enabled: Bool
		)
		case message(
			title: String,
			snippet: String,
			accessibilityLabel: String
		)
		case content(
			result: FileViewerSearchResult,
			query: String
		)
	}

	let primaryLabel: NSTextField
	let detailLabel: NSTextField
	private let presentation: Presentation
	private var sourceLine = ""
	private var query = ""
	private var displayedLine = ""
	private var displayedWidth: CGFloat = 0
	private var selected = false

	init(presentation: Presentation)
	{
		self.presentation = presentation
		if case .content = presentation
		{
			primaryLabel = DesktopTextField(labelWithString: "")
			detailLabel = DesktopTextField(labelWithString: "")
		}
		else
		{
			primaryLabel = NSTextField(labelWithString: "")
			detailLabel = NSTextField(labelWithString: "")
		}
		super.init(frame: .zero)
		switch presentation
		{
		case .chat(
			let title,
			let context,
			let shortcut
		):
			configureInline(
				title: title,
				detail: context,
				shortcut: shortcut,
				inline: false
			)
		case .inlineFile(
			let title,
			let directory,
			let shortcut
		):
			configureInline(
				title: title,
				detail: directory,
				shortcut: shortcut,
				inline: true
			)
		case .inlineCommand(
			let title,
			let detail,
			let leadingAccessory,
			let suffix,
			let opensPicker,
			let enabled
		):
			configureInlineCommand(
				title: title,
				detail: detail,
				leadingAccessory: leadingAccessory,
				suffix: suffix,
				opensPicker: opensPicker,
				enabled: enabled
			)
		case .filename(let path): configureFilename(path)
		case .command(
			let title,
			let detail,
			let enabled
		):
			configureStacked(
				title: title,
				detail: detail,
				titleSize: 13,
				detailSize: 11
			)
			primaryLabel.textColor = enabled ? .labelColor : .tertiaryLabelColor
			detailLabel.lineBreakMode = .byTruncatingMiddle
			setAccessibilityLabel("\(title), \(detail)")
		case .message(
			let title,
			let snippet,
			let accessibilityLabel
		):
			configureStacked(
				title: title,
				detail: snippet,
				titleSize: 12,
				detailSize: nil
			)
			setAccessibilityLabel(accessibilityLabel)
		case .content(
			let result,
			let query
		): configureContent(
				result,
				query: query
			)
		}
	}

	private func configureInline(
		title: String,
		detail: String,
		shortcut: String,
		inline: Bool
	)
	{
		primaryLabel.stringValue = title
		primaryLabel.font = .systemFont(ofSize: 14)
		primaryLabel.lineBreakMode = .byTruncatingMiddle
		detailLabel.stringValue = detail
		detailLabel.font = .systemFont(ofSize: 13)
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingMiddle
		for label in [primaryLabel, detailLabel]
		{
			label.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			label.setContentHuggingPriority(
				.defaultHigh,
				for: .horizontal
			)
		}
		let keycap = DesktopKeycapView(
			shortcut: shortcut,
			presentation: .searchShortcut
		)
		keycap.isHidden = shortcut.isEmpty
		let spacer = NSView()
		let row = AppKitLayout.horizontalStack(
			inline ? [primaryLabel, detailLabel, spacer, keycap]
				: [primaryLabel, spacer, detailLabel, keycap],
			spacing: 8
		)
		installCentered(
			row,
			inset: 8
		)
		detailLabel.widthAnchor.constraint(
			lessThanOrEqualTo: row.widthAnchor,
			multiplier: 0.4
		)
		.isActive = true
		setAccessibilityLabel([title, detail, shortcut].filter
		{
			!$0.isEmpty
		}
		.joined(separator: ", "))
		toolTip = [title, detail].joined(separator: " · ")
	}

	private func configureInlineCommand(
		title: String,
		detail: String,
		leadingAccessory: NSView,
		suffix: String,
		opensPicker: Bool,
		enabled: Bool
	)
	{
		primaryLabel.stringValue = title
		primaryLabel.font = .systemFont(ofSize: 13)
		primaryLabel.textColor = enabled ? .labelColor : .secondaryLabelColor
		if suffix.isEmpty
		{
			primaryLabel.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
		}
		else
		{
			primaryLabel.lineBreakMode = .byTruncatingTail
		}
		detailLabel.stringValue = detail
		detailLabel.font = .systemFont(ofSize: 13)
		detailLabel.textColor = .tertiaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingTail
		detailLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		detailLabel.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		if let icon = leadingAccessory as? NSImageView
		{
			icon.contentTintColor = .secondaryLabelColor
		}
		NSLayoutConstraint.activate([
			leadingAccessory.widthAnchor.constraint(equalToConstant: 16),
			leadingAccessory.heightAnchor.constraint(equalToConstant: 16),
		])
		let row = AppKitLayout.horizontalStack(
			[leadingAccessory, primaryLabel, detailLabel],
			spacing: 8
		)
		row.distribution = .fill
		if !suffix.isEmpty
		{
			let scope = NSTextField(labelWithString: suffix)
			scope.font = .systemFont(ofSize: 12)
			scope.textColor = .secondaryLabelColor
			scope.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
			row.addArrangedSubview(scope)
		}
		if opensPicker
		{
			let chevron = NSImageView(image: NSImage(
				systemSymbolName: "chevron.right",
				accessibilityDescription: nil
			) ?? NSImage())
			chevron.contentTintColor = .tertiaryLabelColor
			NSLayoutConstraint.activate([
				chevron.widthAnchor.constraint(equalToConstant: 10),
				chevron.heightAnchor.constraint(equalToConstant: 12),
			])
			row.addArrangedSubview(chevron)
		}
		installCentered(
			row,
			inset: 10
		)
		setAccessibilityLabel([title, detail, suffix].filter
		{
			!$0.isEmpty
		}
		.joined(separator: ", "))
	}

	private func configureFilename(_ relativePath: String)
	{
		let path = relativePath as NSString
		primaryLabel.stringValue = path.lastPathComponent
		let directory = path.deletingLastPathComponent
		detailLabel.stringValue = directory == "." || directory.isEmpty ? "Top level" : directory
		primaryLabel.font = .systemFont(
			ofSize: 12,
			weight: .medium
		)
		detailLabel.font = .systemFont(ofSize: 11)
		detailLabel.textColor = .secondaryLabelColor
		for label in [primaryLabel, detailLabel]
		{
			label.lineBreakMode = .byTruncatingMiddle
			label.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
		}
		let icon = NSImageView(image: WorkspaceFileIcon.image(relativePath: relativePath))
		icon.imageScaling = .scaleProportionallyDown
		icon.setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		icon.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		let labels = AppKitLayout.verticalStack(
			[primaryLabel, detailLabel],
			spacing: 1
		)
		labels.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let row = AppKitLayout.horizontalStack(
			[icon, labels],
			spacing: 8
		)
		installCentered(
			row,
			inset: 8
		)
		NSLayoutConstraint.activate([
			icon.widthAnchor.constraint(equalToConstant: 16),
			icon.heightAnchor.constraint(equalToConstant: 16),
			labels.widthAnchor.constraint(
				lessThanOrEqualTo: row.widthAnchor,
				constant: -24
			),
		])
		setAccessibilityLabel(relativePath)
		toolTip = relativePath
	}

	private func configureStacked(
		title: String,
		detail: String,
		titleSize: CGFloat,
		detailSize: CGFloat?
	)
	{
		primaryLabel.stringValue = title
		primaryLabel.font = .systemFont(
			ofSize: titleSize,
			weight: .medium
		)
		primaryLabel.lineBreakMode = .byTruncatingTail
		detailLabel.stringValue = detail
		if let detailSize
		{
			detailLabel.font = .systemFont(ofSize: detailSize)
		}
		detailLabel.textColor = .secondaryLabelColor
		detailLabel.lineBreakMode = .byTruncatingTail
		AppKitLayout.pin(
			AppKitLayout.verticalStack(
				[primaryLabel, detailLabel],
				spacing: 2
			),
			to: self,
			inset: 4
		)
	}

	private func installCentered(
		_ content: NSView,
		inset: CGFloat
	)
	{
		content.translatesAutoresizingMaskIntoConstraints = false
		addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: inset
			),
			content.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -inset
			),
			content.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	private func configureContent(
		_ result: FileViewerSearchResult,
		query: String
	)
	{
		sourceLine = result.lineText
		self.query = query
		displayedLine = Self.displayedSnippet(
			result.lineText,
			query: query,
			availableWidth: 150
		)
		let filename = (result.location.relativePath as NSString).lastPathComponent
		detailLabel.stringValue = "\(filename):\(result.lineNumber)"
		primaryLabel.lineBreakMode = .byTruncatingTail
		primaryLabel.maximumNumberOfLines = 1
		primaryLabel.cell?.usesSingleLineMode = true
		primaryLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		primaryLabel.setContentHuggingPriority(
			.defaultLow,
			for: .horizontal
		)
		detailLabel.font = AppKitFontResolver.font(TypographyTokens.FileSearch.location)
		detailLabel.lineBreakMode = .byTruncatingMiddle
		detailLabel.maximumNumberOfLines = 1
		detailLabel.toolTip = "\(result.location.relativePath):\(result.lineNumber)"
		detailLabel.setContentCompressionResistancePriority(
			.defaultHigh,
			for: .horizontal
		)
		detailLabel.setContentHuggingPriority(
			.defaultHigh,
			for: .horizontal
		)
		for label in [primaryLabel, detailLabel]
		{
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)
		}
		NSLayoutConstraint.activate([
			primaryLabel.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			primaryLabel.trailingAnchor.constraint(
				equalTo: detailLabel.leadingAnchor,
				constant: -10
			),
			primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			detailLabel.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -8
			),
			detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			primaryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
			detailLabel.widthAnchor.constraint(
				lessThanOrEqualTo: widthAnchor,
				multiplier: 0.42
			),
			detailLabel.widthAnchor.constraint(
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
		if case .content = presentation
		{
			refreshSnippet()
		}
	}

	override func layout()
	{
		super.layout()
		guard case .content = presentation
		else
		{
			return
		}
		let width = primaryLabel.bounds.width
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
		if case .content = presentation
		{
			refreshSnippet()
		}
	}

	private func refreshSnippet()
	{
		primaryLabel.attributedStringValue = highlightedSnippet()
		detailLabel.textColor = selected
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
