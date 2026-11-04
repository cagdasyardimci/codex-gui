import AppKit

/// Shortcut artwork owns its typography, padding and surface in both views and native cells.
@MainActor
final class DesktopKeycapView: NSView
{
	@MainActor
	enum Presentation
	{
		case fileHint, searchShortcut, toolsShortcut, fileEscape

		var font: NSFont
		{
			AppKitFontResolver.font(role)
		}

		var role: TypographyTokens.Role
		{
			switch self
			{
			case .fileHint: TypographyTokens.FileSearch.footer
			case .fileEscape: TypographyTokens.FileSearch.accessory
			case .searchShortcut: TypographyTokens.Search.shortcut
			case .toolsShortcut: TypographyTokens.Controls.toolsShortcut
			}
		}

		var foreground: NSColor
		{
			switch self
			{
			case .fileHint: AppKitColorTokens.captionText
			case .fileEscape: AppKitColorTokens.primaryText
			case .searchShortcut: AppKitColorTokens.secondaryText
			case .toolsShortcut: AppKitColorTokens.toolsTileIcon
			}
		}

		var background: NSColor
		{
			switch self
			{
			case .fileHint: AppKitColorTokens.fileSearchKeycap
			case .fileEscape: AppKitColorTokens.fileSearchEscape
			case .searchShortcut: AppKitColorTokens.shortcutSurface
			case .toolsShortcut: AppKitColorTokens.toolsShortcut
			}
		}

		var horizontalInset: CGFloat
		{
			switch self
			{
			case .fileHint, .fileEscape: LayoutTokens.FileSearch.keycapHorizontalInset
			case .searchShortcut: 2
			case .toolsShortcut: LayoutTokens.Tabs.toolShortcutHorizontalInset
			}
		}

		var cornerRadius: CGFloat
		{
			switch self
			{
			case .fileHint, .fileEscape: ShapeTokens.FileSearch.keycapRadius
			case .searchShortcut: 7
			case .toolsShortcut: ShapeTokens.TabControls.toolShortcutRadius
			}
		}
	}

	private let presentation: Presentation

	init(
		shortcut: String,
		presentation: Presentation
	)
	{
		self.presentation = presentation
		super.init(frame: .zero)
		let label: NSTextField = presentation == .fileHint
			? DesktopTextField(labelWithString: shortcut) : NSTextField(labelWithString: shortcut)
		label.setTypographyRole(presentation.role)
		label.textColor = presentation.foreground
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		if presentation == .searchShortcut
		{
			AppKitLayout.pin(
				label,
				to: self,
				inset: 2
			)
			label.setContentCompressionResistancePriority(
				.required,
				for: .horizontal
			)
		}
		else
		{
			NSLayoutConstraint.activate([
				heightAnchor.constraint(equalToConstant: Self.size(
					for: shortcut,
					presentation: presentation
				).height),
				label.leadingAnchor.constraint(
					equalTo: leadingAnchor,
					constant: presentation.horizontalInset
				),
				label.trailingAnchor.constraint(
					equalTo: trailingAnchor,
					constant: -presentation.horizontalInset
				),
				label.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	static func size(
		for shortcut: String,
		presentation: Presentation,
		font: NSFont? = nil
	) -> NSSize
	{
		let text = (shortcut as NSString).size(withAttributes: [.font: font ?? presentation.font])
		let height: CGFloat
		switch presentation
		{
		case .fileHint: height = LayoutTokens.FileSearch.keycapHeight
		case .fileEscape: return NSSize(
				width: max(
					LayoutTokens.FileSearch.escapeWidth,
					text.width + 2 * presentation.horizontalInset
				),
				height: max(
					LayoutTokens.FileSearch.escapeHeight,
					text.height
				)
			)
		case .searchShortcut: height = text.height + 4
		case .toolsShortcut: height = LayoutTokens.Tabs.toolShortcutHeight
		}
		return NSSize(
			width: text.width + 2 * presentation.horizontalInset,
			height: height
		)
	}

	static func draw(
		shortcut: String,
		in rect: NSRect,
		presentation: Presentation,
		owner: NSView
	)
	{
		DesktopKeycapDrawing.fill(
			rect,
			color: presentation.background,
			cornerRadius: presentation.cornerRadius
		)
		let color = NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
			presentation.foreground,
			for: owner
		)) ?? presentation.foreground
		let title = NSAttributedString(
			string: shortcut,
			attributes: [
				.font: presentation.font,
				.foregroundColor: color,
			]
		)
		title.draw(in: NSRect(
			x: rect.minX + presentation.horizontalInset,
			y: rect.midY - title.size().height / 2,
			width: title.size().width,
			height: title.size().height
		))
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect)
	{
		DesktopKeycapDrawing.fill(
			bounds,
			color: presentation.background,
			cornerRadius: presentation.cornerRadius
		)
	}
}
