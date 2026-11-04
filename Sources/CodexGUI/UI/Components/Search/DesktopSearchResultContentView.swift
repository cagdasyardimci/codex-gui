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
			shortcut: String,
			query: String,
			showsIcon: Bool
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
		primaryLabel.textColor = AppKitColorTokens.primaryText
		switch presentation
		{
		case .chat(
			let title,
			let context,
			let shortcut,
			let query,
			let showsIcon
		):
			configureInline(
				title: title,
				detail: context,
				shortcut: shortcut,
				inline: false,
				query: query,
				showsIcon: showsIcon
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
				titleRole: TypographyTokens.Search.commandTitle,
				detailRole: TypographyTokens.Search.commandDetail
			)
			primaryLabel.textColor = enabled ? AppKitColorTokens.primaryText : AppKitColorTokens
				.mutedText
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
				titleRole: TypographyTokens.Search.messageTitle,
				detailRole: TypographyTokens.Search.messageSnippet
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
		inline: Bool,
		query: String = "",
		showsIcon: Bool = false,
		leadingImage: NSImage? = nil
	)
	{
		primaryLabel.stringValue = title
		primaryLabel.setTypographyRole(TypographyTokens.Search.resultTitle)
		primaryLabel.lineBreakMode = .byTruncatingMiddle
		detailLabel.stringValue = detail
		detailLabel.setTypographyRole(TypographyTokens.Search.resultDetail)
		detailLabel.textColor = AppKitColorTokens.secondaryText
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
		var items: [NSView] = inline ? [primaryLabel, detailLabel, spacer, keycap]
			: [primaryLabel, spacer, detailLabel, keycap]
		if showsIcon || leadingImage != nil
		{
			let icon = NSImageView(image: leadingImage ?? NSImage(
				systemSymbolName: "bubble.left",
				accessibilityDescription: nil
			) ?? NSImage())
			icon.contentTintColor = AppKitColorTokens.secondaryText
			icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
			icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
			items.insert(
				icon,
				at: 0
			)
		}
		if !query.isEmpty
		{
			let text = NSMutableAttributedString(
				string: title,
				attributes: [
					.font: AppKitFontResolver.font(TypographyTokens.Search.resultTitle),
					.foregroundColor: AppKitColorTokens.secondaryText,
				]
			)
			let source = title as NSString
			var start = 0
			while start < source.length
			{
				let match = source.range(
					of: query,
					options: [.caseInsensitive, .literal],
					range: NSRange(
						location: start,
						length: source.length - start
					)
				)
				guard match.location != NSNotFound, match.length > 0
				else
				{
					break
				}
				text.addAttribute(
					.foregroundColor,
					value: AppKitColorTokens.primaryText,
					range: match
				)
				start = NSMaxRange(match)
			}
			primaryLabel.attributedStringValue = text
		}
		let row = AppKitLayout.horizontalStack(
			items,
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
		primaryLabel.setTypographyRole(TypographyTokens.Search.resultDetail)
		primaryLabel.textColor = enabled ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
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
		detailLabel.setTypographyRole(TypographyTokens.Search.resultDetail)
		detailLabel.textColor = AppKitColorTokens.mutedText
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
			icon.contentTintColor = AppKitColorTokens.secondaryText
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
			scope.setTypographyRole(TypographyTokens.Search.resultSection)
			scope.textColor = AppKitColorTokens.secondaryText
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
			chevron.contentTintColor = AppKitColorTokens.mutedText
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
		let directory = path.deletingLastPathComponent
		configureInline(
			title: path.lastPathComponent,
			detail: directory == "." || directory.isEmpty ? "Top level" : directory,
			shortcut: "",
			inline: false,
			leadingImage: WorkspaceFileIcon.image(relativePath: relativePath)
		)
		setAccessibilityLabel(relativePath)
		toolTip = relativePath
	}

	private func configureStacked(
		title: String,
		detail: String,
		titleRole: TypographyTokens.Role,
		detailRole: TypographyTokens.Role
	)
	{
		primaryLabel.stringValue = title
		primaryLabel.setTypographyRole(titleRole)
		primaryLabel.lineBreakMode = .byTruncatingTail
		detailLabel.stringValue = detail
		detailLabel.setTypographyRole(detailRole)
		detailLabel.textColor = AppKitColorTokens.secondaryText
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
		detailLabel.setTypographyRole(TypographyTokens.FileSearch.location)
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
		let icon = NSImageView(image: NSImage(
			systemSymbolName: "doc",
			accessibilityDescription: nil
		) ?? NSImage())
		icon.contentTintColor = AppKitColorTokens.secondaryText
		icon.translatesAutoresizingMaskIntoConstraints = false
		addSubview(icon)
		for label in [primaryLabel, detailLabel]
		{
			label.translatesAutoresizingMaskIntoConstraints = false
			addSubview(label)
		}
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 8
			),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: 16),
			icon.heightAnchor.constraint(equalToConstant: 16),
			primaryLabel.leadingAnchor.constraint(
				equalTo: icon.trailingAnchor,
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
		clippedPrefix(text)
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
