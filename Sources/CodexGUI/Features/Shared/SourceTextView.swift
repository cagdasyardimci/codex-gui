import AppKit

/// Native source behavior and styling shared by Files and Changes.
@MainActor
class SourceTextView: NSTextView
{
	static let sourceFont = AppKitFontResolver.font(TypographyTokens.Transcript.code)
	static let sourceLineHeight: CGFloat = 22
	private var sourceWrapsLines = true

	func configureSourceText(wrapsLines: Bool)
	{
		isRichText = false
		importsGraphics = false
		isSelectable = true
		isAutomaticLinkDetectionEnabled = false
		isAutomaticQuoteSubstitutionEnabled = false
		isAutomaticDashSubstitutionEnabled = false
		isAutomaticTextReplacementEnabled = false
		isAutomaticSpellingCorrectionEnabled = false
		isContinuousSpellCheckingEnabled = false
		isGrammarCheckingEnabled = false
		isAutomaticDataDetectionEnabled = false
		font = Self.sourceFont
		refreshSourceAppearance(
			appearance: effectiveAppearance,
			wrapsLines: wrapsLines
		)
	}

	func refreshSourceAppearance(
		appearance: NSAppearance,
		wrapsLines: Bool
	)
	{
		sourceWrapsLines = wrapsLines
		backgroundColor = .textBackgroundColor
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let baseColor: NSColor = dark ? .labelColor : .black
		// NSTextView.textColor rewrites all glyph attributes after the owner applies syntax colors.
		insertionPointColor = baseColor
		let style = Self.paragraphStyle(wrapsLines: wrapsLines)
		defaultParagraphStyle = style
		typingAttributes[.font] = Self.sourceFont
		typingAttributes[.paragraphStyle] = style
		typingAttributes[.foregroundColor] = baseColor
	}

	static func paragraphStyle(wrapsLines: Bool) -> NSMutableParagraphStyle
	{
		let style = NSMutableParagraphStyle()
		style.minimumLineHeight = sourceLineHeight
		style.maximumLineHeight = sourceLineHeight
		style.lineBreakMode = wrapsLines ? .byCharWrapping : .byClipping
		style.tabStops = []
		style.defaultTabInterval = ("    " as NSString).size(
			withAttributes: [.font: sourceFont]
		).width
		return style
	}

	/// Applies source attributes in place so Files can retain text storage and undo history.
	static func applySourceStyle(
		to attributed: NSMutableAttributedString,
		text: String,
		path: String,
		appearance: NSAppearance,
		wrapsLines: Bool
	)
	{
		guard attributed.length > 0
		else
		{
			return
		}
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		let range = NSRange(
			location: 0,
			length: attributed.length
		)
		attributed.addAttributes(
			[
				.font: sourceFont,
				.foregroundColor: dark ? NSColor.labelColor : NSColor.black,
				.paragraphStyle: paragraphStyle(wrapsLines: wrapsLines)
			],
			range: range
		)
		let extensionName = (path as NSString).pathExtension.lowercased()
		if extensionName == "md" || extensionName == "markdown"
		{
			MarkdownSourceStyling.apply(
				to: attributed,
				source: text,
				dark: dark
			)
			return
		}
		let language = CodePreviewPresentation.language(for: path)
		guard let colors = CodeSyntaxHighlighter.highlightedCode(
			text,
			language: language,
			dark: dark
		), colors.length == attributed.length
		else
		{
			return
		}
		colors.enumerateAttribute(
			.foregroundColor,
			in: range
		)
		{
			color, coloredRange, _ in
			if let color
			{
				attributed.addAttribute(
					.foregroundColor,
					value: color,
					range: coloredRange
				)
			}
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshSourceAppearance(
			appearance: effectiveAppearance,
			wrapsLines: sourceWrapsLines
		)
	}

	override func keyDown(with event: NSEvent)
	{
		if !isEditable,
			!event.modifierFlags.contains(.command),
			!event.modifierFlags.contains(.control),
			let characters = event.charactersIgnoringModifiers,
			characters.unicodeScalars.contains(where:
			{
				$0.value >= 0x20 && $0.value < 0xF700 || $0.value == 0x7F
			})
		{
			return
		}
		super.keyDown(with: event)
	}

	override func insertText(
		_ string: Any,
		replacementRange: NSRange
	)
	{
		guard isEditable
		else
		{
			return
		}
		super.insertText(
			string,
			replacementRange: replacementRange
		)
	}
}
