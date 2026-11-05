import AppKit

/// Displays recorded result text without Markdown interpretation or link activation.
@MainActor
final class SourceResultCodeCard: DesktopOutputCard
{
	private let source: String
	private let language: String
	private let textView = NSTextView()
	private let scroll: NSScrollView
	private var font: NSFont
	{
		AppKitFontResolver.font(TypographyTokens.Code.output)
	}
	private var typographyObservation: TypographyObservation?
	private var codeSize = NSSize.zero
	private var bodyHeightConstraint: NSLayoutConstraint?

	init(
		text: String,
		language: String,
		identifier: String,
		maximumBodyHeight: CGFloat = 188,
		headerAccessory: NSView? = nil
	)
	{
		let boundedSource = text.count > 16384 ? String(text.prefix(16384)) + "\n[Truncated]" : text
		let normalizedLanguage = language.lowercased() == "json" ? "json" : "text"
		self.source = boundedSource
		self.language = normalizedLanguage
		let resultScroll = NSScrollView()
		scroll = resultScroll
		super.init(
			title: normalizedLanguage,
			presentation: .code,
			body: resultScroll,
			accessory: headerAccessory
		)
		self.identifier = NSUserInterfaceItemIdentifier(identifier)
		textView.identifier = NSUserInterfaceItemIdentifier(identifier + ":text")
		textView.isEditable = false
		textView.isSelectable = true
		textView.isRichText = true
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isAutomaticDataDetectionEnabled = false
		textView.drawsBackground = false
		textView.isHorizontallyResizable = true
		textView.isVerticallyResizable = true
		textView.textContainerInset = NSSize(
			width: 0,
			height: 4
		)
		textView.textContainer?.lineFragmentPadding = 0
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.containerSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.setAccessibilityLabel("Recorded \(normalizedLanguage) result")
		scroll.hasHorizontalScroller = true
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		scroll.documentView = textView
		typographyObservation = TypographyObservation
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.applyColors()
			if let container = self.textView.textContainer, let layout = self.textView.layoutManager
			{
				layout.ensureLayout(for: container)
				self.codeSize = layout.usedRect(for: container).size
			}
			self.bodyHeightConstraint?.constant = min(
				maximumBodyHeight,
				max(
					64,
					ceil(self.codeSize.height) + 20
				)
			)
			self.needsLayout = true
		}
		applyColors()
		if let container = textView.textContainer, let layout = textView.layoutManager
		{
			layout.ensureLayout(for: container)
			codeSize = layout.usedRect(for: container).size
		}
		let bodyHeight = min(
			maximumBodyHeight,
			max(
				64,
				ceil(codeSize.height) + 20
			)
		)
		bodyHeightConstraint = scroll.heightAnchor.constraint(equalToConstant: bodyHeight)
		bodyHeightConstraint?.isActive = true
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func layout()
	{
		super.layout()
		textView.setFrameSize(NSSize(
			width: max(
				scroll.contentSize.width,
				ceil(codeSize.width) + 2
			),
			height: max(
				scroll.contentSize.height,
				ceil(codeSize.height) + 8
			)
		))
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		applyColors()
	}

	private func applyColors()
	{
		let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = TypographyTokens.Code.output.lineHeight ?? 0
		paragraph.maximumLineHeight = 0
		let text = NSMutableAttributedString(
			string: source,
			attributes: [
				.font: font,
				.foregroundColor: AppKitColorTokens.primaryText,
				.paragraphStyle: paragraph,
			]
		)
		if language == "json", let highlighted = CodeSyntaxHighlighter.highlightedCode(
			source,
			language: "json",
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
				value, range, _ in
				if let color = value as? NSColor
				{
					text.addAttribute(
						.foregroundColor,
						value: color,
						range: range
					)
				}
			}
		}
		let selection = textView.selectedRange()
		textView.textStorage?.setAttributedString(text)
		let location = min(
			selection.location,
			text.length
		)
		textView.setSelectedRange(NSRange(
			location: location,
			length: min(
				selection.length,
				text.length - location
			)
		))
	}
	/// Screenshot samples converted from their embedded display profile to sRGB.
	static var activityTitleColor: NSColor
	{
		AppKitColorTokens.primaryText
	}

	static var activityLabelColor: NSColor
	{
		AppKitColorTokens.secondaryText
	}

}
