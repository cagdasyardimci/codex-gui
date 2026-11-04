import AppKit

/// Token colors are selected once from the configured code theme for all native syntax consumers.
@MainActor
enum SyntaxColorTokens
{
	static func theme(
		profile: ColorThemeProfile,
		dark: Bool,
		markdown: Bool
	) -> MeasuredCodeThemeColors.Theme?
	{
		if let id = profile.codeThemeID,
			let theme = MeasuredCodeThemeColors.themes[id]
		{
			return theme
		}
		if markdown && dark
		{
			return MeasuredCodeThemeColors.markdownDark(foreground: profile.foreground)
		}
		return MeasuredCodeThemeColors.themes[dark ? "Codex Dark" : "Codex Light"]
	}
	static func fallbackHighlighterTheme(dark: Bool) -> String
	{
		dark ? "github-dark" : "github"
	}

	static func color(
		_ role: String,
		dark: Bool,
		configuration: ColorThemeConfiguration = ColorPreferences().configuration
	) -> NSColor
	{
		let profile = dark ? configuration.dark : configuration.light
		let theme = theme(
			profile: profile,
			dark: dark,
			markdown: false
		)
			?? MeasuredCodeThemeColors.themes[dark ? "Codex Dark" : "Codex Light"]
		let hex = theme?.colors[role] ?? theme?.foreground
		return hex.flatMap(AppKitColorResolution.hexColor) ?? AppKitColorTokens.primaryText
	}
}
