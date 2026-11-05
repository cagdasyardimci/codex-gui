import AppKit

/// Native source behavior and styling shared by Files and Changes.
@MainActor
class SourceTextView: NSTextView
{
	static var sourceFont: NSFont
	{
		AppKitFontResolver.font(TypographyTokens.Code.source)
	}
	static var sourceLineHeight: CGFloat
	{
		TypographyTokens.Code.source.lineHeight ?? 22
	}
	private var typographyObservation: TypographyObservation?
	private var themeColorObservation: ThemeColorObservation?
	var onTypographyChange: (() -> Void)?
	private var sourceWrapsLines = true
	class var typographyRole: TypographyTokens.Role
	{
		TypographyTokens.Code.source
	}

	func configureSourceText(wrapsLines: Bool)
	{
		themeColorObservation = ThemeColorObservation
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			self.refreshSourceAppearance(
				appearance: self.effectiveAppearance,
				wrapsLines: self.sourceWrapsLines
			)
			self.needsDisplay = true
		}
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
		typographyObservation = TypographyObservation(view: self)
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let selection = self.selectedRanges
			let font = AppKitFontResolver.font(
				type(of: self).typographyRole,
				appearance: self.effectiveAppearance
			)
			self.font = font
			let paragraph = Self.paragraphStyle(
				wrapsLines: self.sourceWrapsLines,
				role: type(of: self).typographyRole
			)
			self.defaultParagraphStyle = paragraph
			self.typingAttributes[.font] = font
			self.typingAttributes[.paragraphStyle] = paragraph
			if let storage = self.textStorage, storage.length > 0
			{
				storage.addAttributes(
					[.font: font, .paragraphStyle: paragraph],
					range: NSRange(
						location: 0,
						length: storage.length
					)
				)
			}
			self.selectedRanges = selection
			self.onTypographyChange?()
			self.needsDisplay = true
		}
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
		backgroundColor = AppKitColorTokens.editorSurface
		let baseColor = AppKitColorTokens.primaryText
		// NSTextView.textColor rewrites all glyph attributes after the owner applies syntax colors.
		insertionPointColor = baseColor
		let style = Self.paragraphStyle(
			wrapsLines: wrapsLines,
			role: type(of: self).typographyRole
		)
		defaultParagraphStyle = style
		typingAttributes[.font] = AppKitFontResolver.font(
			type(of: self).typographyRole,
			appearance: appearance
		)
		typingAttributes[.paragraphStyle] = style
		typingAttributes[.foregroundColor] = baseColor
	}

	static func paragraphStyle(
		wrapsLines: Bool,
		role: TypographyTokens.Role = TypographyTokens.Code.source
	) -> NSMutableParagraphStyle
	{
		let style = NSMutableParagraphStyle()
		style.minimumLineHeight = role.lineHeight ?? sourceLineHeight
		style.maximumLineHeight = role.lineHeight ?? sourceLineHeight
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
		wrapsLines: Bool,
		role: TypographyTokens.Role = TypographyTokens.Code.source
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
				.font: AppKitFontResolver.font(
					role,
					appearance: appearance
				),
				.foregroundColor: AppKitColorTokens.primaryText,
				.paragraphStyle: paragraphStyle(
					wrapsLines: wrapsLines,
					role: role
				)
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
		let language = CodePreviewPresentation(
			text: text,
			relativePath: path
		).language
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
