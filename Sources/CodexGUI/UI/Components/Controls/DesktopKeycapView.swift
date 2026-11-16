import AppKit

/// Shortcut artwork owns its typography, padding and surface in both views and native cells.
@MainActor
final class DesktopKeycapView: NSView
{
	@MainActor
	enum Presentation
	{
		case fileHint, searchShortcut, toolsShortcut, fileEscape, question, questionSelected

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
			case .question, .questionSelected: TypographyTokens.MenuRow.title
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
			case .question: AppKitColorTokens.secondaryText
			case .questionSelected: AppKitColorTokens.elevated
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
			case .question: AppKitColorTokens.input
			case .questionSelected: AppKitColorTokens.primaryText
			}
		}

		var horizontalInset: CGFloat
		{
			switch self
			{
			case .fileHint, .fileEscape: LayoutTokens.FileSearch.keycapHorizontalInset
			case .searchShortcut, .question, .questionSelected: 2
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
			case .question, .questionSelected: 4
			}
		}
	}

	private let presentation: Presentation
	private let shortcut: String
	private var questionSurface: NSView?

	var questionSurfaceBounds: NSRect?
	{
		guard let questionSurface
		else
		{
			return nil
		}
		layoutSubtreeIfNeeded()
		return convert(
			questionSurface.bounds,
			from: questionSurface
		)
	}

	init(
		shortcut: String,
		presentation: Presentation
	)
	{
		self.presentation = presentation
		self.shortcut = shortcut
		super.init(frame: .zero)
		let label: NSTextField = presentation == .fileHint
			? DesktopTextField(labelWithString: shortcut) : NSTextField(labelWithString: shortcut)
		if presentation == .question || presentation == .questionSelected
		{
			label.alignment = .center
		}
		label.setTypographyRole(presentation.role)
		label.textColor = presentation.foreground
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		if presentation == .question || presentation == .questionSelected
		{
			let surface = QuestionSurface(presentation: presentation)
			questionSurface = surface
			surface.translatesAutoresizingMaskIntoConstraints = false
			addSubview(
				surface,
				positioned: .below,
				relativeTo: label
			)
			let attributes = AppKitFontResolver.textAttributes(TypographyTokens.MenuRow.title)
			let paragraph = (attributes[.paragraphStyle] as! NSParagraphStyle)
				.mutableCopy() as! NSMutableParagraphStyle
			paragraph.alignment = .center
			let title = NSMutableAttributedString(attributedString: label.attributedStringValue)
			title.addAttribute(
				.paragraphStyle,
				value: paragraph,
				range: NSRange(
					location: 0,
					length: title.length
				)
			)
			label.attributedStringValue = title
			NSLayoutConstraint.activate([
				surface.widthAnchor.constraint(equalTo: widthAnchor),
				surface.heightAnchor.constraint(equalTo: heightAnchor),
				surface.centerXAnchor.constraint(equalTo: centerXAnchor),
				// The badge follows the visible numeral, whose ink occupies the cap-height box.
				surface.centerYAnchor.constraint(
					equalTo: label.firstBaselineAnchor,
					constant: -presentation.font.capHeight / 2
				),
				label.heightAnchor.constraint(equalToConstant: paragraph.minimumLineHeight),
				label.leadingAnchor.constraint(equalTo: leadingAnchor),
				label.trailingAnchor.constraint(equalTo: trailingAnchor),
				label.centerYAnchor.constraint(equalTo: centerYAnchor),
			])
		}
		else if presentation == .searchShortcut
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
		case .question, .questionSelected:
			let side = max(
				20,
				ceil(max(
					text.width,
					text.height
				) + 4)
			)
			return NSSize(
				width: side,
				height: side
			)
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
		drawSurface(
			in: rect,
			presentation: presentation
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
		let titleX = presentation == .question || presentation == .questionSelected
			? rect.midX - title.size().width / 2 : rect.minX + presentation.horizontalInset
		title.draw(in: NSRect(
			x: titleX,
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
		guard presentation != .question && presentation != .questionSelected
		else
		{
			return
		}
		Self.drawSurface(
			in: bounds,
			presentation: presentation
		)
	}

	private final class QuestionSurface: NSView
	{
		let presentation: Presentation

		init(presentation: Presentation)
		{
			self.presentation = presentation
			super.init(frame: .zero)
		}

		required init?(coder: NSCoder)
		{
			nil
		}

		override func draw(_ dirtyRect: NSRect)
		{
			DesktopKeycapView.drawSurface(
				in: bounds,
				presentation: presentation
			)
		}
	}

	private static func drawSurface(
		in rect: NSRect,
		presentation: Presentation
	)
	{
		DesktopKeycapDrawing.fill(
			rect,
			color: presentation.background,
			cornerRadius: presentation.cornerRadius
		)
		if presentation == .question
		{
			AppKitColorTokens.border.setStroke()
			let outline = NSBezierPath(
				roundedRect: rect.insetBy(
					dx: 0.5,
					dy: 0.5
				),
				xRadius: presentation.cornerRadius,
				yRadius: presentation.cornerRadius
			)
			outline.lineWidth = 1
			outline.stroke()
		}
	}
}
