import AppKit

/// Keyboard hints keep key artwork and explanatory labels in one presentation owner.
@MainActor
class DesktopShortcutHintsView: NSStackView
{
	init(hints: [(shortcut: String, title: String)])
	{
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = LayoutTokens.FileSearch.hintGroupSpacing
		setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		for hint in hints
		{
			let label = DesktopTextField(labelWithString: hint.title)
			label.font = AppKitFontResolver.font(TypographyTokens.FileSearch.footer)
			label.textColor = AppKitColorTokens.captionText
			let keycap = DesktopKeycapView(
				shortcut: hint.shortcut,
				presentation: .fileHint
			)
			addArrangedSubview(AppKitLayout.horizontalStack(
				[keycap, label],
				spacing: LayoutTokens.FileSearch.hintSpacing
			))
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
