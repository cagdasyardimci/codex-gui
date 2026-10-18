import AppKit

@MainActor
final class FileSearchKeyboardHintsView: NSStackView
{
	init()
	{
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = LayoutTokens.FileSearch.hintGroupSpacing
		setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		addArrangedSubview(Self.hint(
			shortcut: "↑ ↓",
			title: "navigate"
		))
		addArrangedSubview(Self.hint(
			shortcut: "↵",
			title: "open"
		))
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	private static func hint(
		shortcut: String,
		title: String
	) -> NSView
	{
		let label = FileSearchTextField(labelWithString: title)
		label.font = AppKitFontResolver.font(TypographyTokens.FileSearch.footer)
		label.textColor = AppKitColorTokens.captionText
		let group = NSStackView(views: [FileSearchKeycapView(shortcut: shortcut), label])
		group.orientation = .horizontal
		group.alignment = .centerY
		group.spacing = LayoutTokens.FileSearch.hintSpacing
		return group
	}
}

@MainActor
private final class FileSearchKeycapView: NSView
{
	init(shortcut: String)
	{
		super.init(frame: .zero)
		let label = FileSearchTextField(labelWithString: shortcut)
		label.font = AppKitFontResolver.font(TypographyTokens.FileSearch.footer)
		label.textColor = AppKitColorTokens.captionText
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: LayoutTokens.FileSearch.keycapHeight),
			label.leadingAnchor.constraint(
				equalTo: leadingAnchor,
				constant: LayoutTokens.FileSearch.keycapHorizontalInset
			),
			label.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -LayoutTokens.FileSearch.keycapHorizontalInset
			),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		AppKitColorTokens.fileSearchKeycap.setFill()
		NSBezierPath(
			roundedRect: bounds,
			xRadius: ShapeTokens.FileSearch.keycapRadius,
			yRadius: ShapeTokens.FileSearch.keycapRadius
		).fill()
	}
}
