import AppKit

/// Displays recorded result text without Markdown interpretation or link activation.
@MainActor
final class SourceResultCodeCard: DesktopOutputCard
{
	private let source: String
	private let language: String
	private let textView = NSTextView()
	private let scroll: NSScrollView
	private let font = NSFont.monospacedSystemFont(
		ofSize: 12,
		weight: .light
	)
	private var codeSize = NSSize.zero

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
		scroll.heightAnchor.constraint(equalToConstant: bodyHeight).isActive = true
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
		paragraph.minimumLineHeight = 20
		paragraph.maximumLineHeight = 20
		let text = NSMutableAttributedString(
			string: source,
			attributes: [
				.font: font,
				.foregroundColor: Self.referenceColor(
					0x191C1F,
					dark: .white
				),
				.paragraphStyle: paragraph,
			]
		)
		if language == "json"
		{
			applyJSONColors(
				to: text,
				dark: dark
			)
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
	private func applyJSONColors(
		to text: NSMutableAttributedString,
		dark: Bool
	)
	{
		// Matches entire escaped strings before considering numbers and JSON literals.
		let pattern = #""(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b"#
		guard let regex = try? NSRegularExpression(pattern: pattern)
		else
		{
			return
		}
		let source = text.string as NSString
		for match in regex.matches(
			in: text.string,
			range: NSRange(
				location: 0,
				length: text.length
			)
		)
		{
			let token = source.substring(with: match.range)
			let color: NSColor
			if token.hasPrefix("\"")
			{
				let tail = source.substring(from: NSMaxRange(match.range))
					.trimmingCharacters(in: .whitespacesAndNewlines)
				if tail.hasPrefix(":")
				{
					color = dark
						? Self.sRGB(0xF9DC78)
						: Self.sRGB(0xB8802A)
				}
				else
				{
					color = dark
						? Self.sRGB(0x83D197)
						: Self.sRGB(0x3B843F)
				}
			}
			else if token == "true" || token == "false" || token == "null"
			{
				color = dark ? Self.sRGB(0xF8A6C8) : Self.sRGB(0xAB4F7A)
			}
			else
			{
				color = dark ? Self.sRGB(0xF2A174) : Self.sRGB(0xAC4F24)
			}
			text.addAttribute(
				.foregroundColor,
				value: color,
				range: match.range
			)
		}
	}

	/// Screenshot samples converted from their embedded display profile to sRGB.
	static var activityTitleColor: NSColor
	{
		referenceColor(
			0x191C1F,
			dark: .white
		)
	}

	static var activityLabelColor: NSColor
	{
		referenceColor(
			0x767778,
			dark: sRGB(0xA3A3A3)
		)
	}

	private static func sRGB(_ hex: UInt32) -> NSColor
	{
		NSColor(
			srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
			green: CGFloat((hex >> 8) & 0xFF) / 255,
			blue: CGFloat(hex & 0xFF) / 255,
			alpha: 1
		)
	}

	private static func referenceColor(
		_ hex: UInt32,
		dark: NSColor
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : sRGB(hex)
		}
	}

}
