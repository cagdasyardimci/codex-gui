import Foundation

extension TypographyTokens
{
	enum Settings
	{
		static let sizeInput = TypographyTokens.Text.menu
		static let editorOption = TypographyTokens.Text.label
		static let choiceDescription = TypographyTokens.Text.menu
		static let choiceSection = TypographyTokens.Text.detail
		static let search = Role(
			size: 14,
			selection: .interface(weight: .text),
			lineHeight: 18
		)
		static let sidebarRow = Role(
			rule: .ui(offset: 0),
			selection: .interface(weight: .regular),
			lineHeight: .multiple(10.0 / 7)
		)
		static let heading = Role(
			rule: .heading(18),
			selection: .family(
				"OpenAI Sans",
				weight: .strong
			),
			lineHeight: .fixed(24)
		)
		static let editorTitle = TypographyTokens.Text.heading(
			20,
			weight: .regular
		)
		static let section = TypographyTokens.Text.control
		static let rowLabel = TypographyTokens.Text.menu
		// Form page titles have the same scale as landing titles, without heading emphasis.
		static let formTitle = Role(
			rule: TypographyTokens.Connections.title.sizeRule,
			selection: TypographyTokens.Text.input.selection,
			lineHeight: TypographyTokens.Connections.title.lineHeightRule
		)
	}
}
