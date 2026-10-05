import AppKit

/// Displays recorded result text without Markdown interpretation or link activation.
@MainActor
final class SourceResultCodeCard: NSView
{
	private let source: String
	private let language: String
	private let isError: Bool
	private let textView = NSTextView()
	private let scroll = NSScrollView()
	private let font = NSFont.monospacedSystemFont(
		ofSize: 12,
		weight: .light
	)
	private var codeSize = NSSize.zero

	init(
		text: String,
		language: String,
		identifier: String,
		isError: Bool = false,
		maximumBodyHeight: CGFloat = 188,
		headerAccessory: NSView? = nil
	)
	{
		self.source = text.count > 16384 ? String(text.prefix(16384)) + "\n[Truncated]" : text
		self.language = language.lowercased() == "json" ? "json" : "text"
		self.isError = isError
		super.init(frame: .zero)
		self.identifier = NSUserInterfaceItemIdentifier(identifier)
		wantsLayer = true
		layer?.cornerRadius = isError ? 12 : 20
		layer?.borderWidth = 1
		if isError
		{
			let notice = NSTextField(wrappingLabelWithString: source)
			notice.font = .systemFont(
				ofSize: 14,
				weight: .light
			)
			notice.textColor = Self.referenceColor(
				0x191C1F,
				dark: .white
			)
			notice.isSelectable = true
			notice.identifier = NSUserInterfaceItemIdentifier(identifier + ":text")
			notice.setContentCompressionResistancePriority(
				.defaultLow,
				for: .horizontal
			)
			notice.setAccessibilityLabel("Recorded error: \(source)")
			AppKitLayout.pin(
				notice,
				to: self,
				inset: 12
			)
			applyColors()
			return
		}
		let icon = NSImageView()
		icon.image = DesktopIcons.image(
			.code,
			size: 20
		)
		icon.setAccessibilityElement(false)
		icon.contentTintColor = Self.referenceColor(
			0x191C1F,
			dark: .white
		)
		icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
		icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
		let label = NSTextField(labelWithString: self.language)
		label.font = .systemFont(
			ofSize: 13,
			weight: .regular
		)
		label.textColor = Self.referenceColor(
			0x191C1F,
			dark: .white
		)
		let headerViews: [NSView] = headerAccessory.map
		{
			[icon, label, NSView(), $0]
		}
		?? [icon, label]
		let header = AppKitLayout.horizontalStack(
			headerViews,
			spacing: 6
		)
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
		textView.setAccessibilityLabel("Recorded \(self.language) result")
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
		addSubview(header)
		addSubview(scroll)
		header.translatesAutoresizingMaskIntoConstraints = false
		scroll.translatesAutoresizingMaskIntoConstraints = false
		if headerAccessory != nil
		{
			header.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -21
			).isActive = true
		}
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 21
			),
			header.trailingAnchor.constraint(
				lessThanOrEqualTo: trailingAnchor,
				constant: -21
			),
			header.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 16
			),
			scroll.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: 21
			),
			scroll.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -21
			),
			scroll.topAnchor.constraint(
				equalTo: header.bottomAnchor,
				constant: 6
			),
			scroll.bottomAnchor.constraint(
				equalTo: bottomAnchor,
				constant: -12
			),
			scroll.heightAnchor.constraint(equalToConstant: bodyHeight),
		])
	}

	required init?(coder: NSCoder)
	{
		return nil
	}

	override func layout()
	{
		super.layout()
		guard !isError
		else
		{
			return
		}
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
		if isError
		{
			layer?.backgroundColor = (dark
				? Self.sRGB(0x270B0A) : Self.sRGB(0xFEF1F0)).cgColor
			layer?.borderColor = (dark
				? Self.sRGB(0x7C221F) : Self.sRGB(0xFBD5D3)).cgColor
			return
		}
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
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			layer?.backgroundColor = (dark
				? Self.sRGB(0x2A2A2A) : Self.sRGB(0xF3F3F3)).cgColor
			layer?.borderColor = (dark ? Self.sRGB(0x333333) : Self.sRGB(0xE8E8E8)).cgColor
		}
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
