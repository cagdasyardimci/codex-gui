import Foundation

/// Reference-measured app-color profiles; code-theme names remain renderer identifiers.
struct ColorThemePreset: Sendable
{
	let id: String
	let label: String
	let appearance: ColorAppearance
	let codeTheme: String
	let uiFontFamily: String?
	let codeFontFamily: String?
	let contentFontFamily: String?
	let opaqueWindows: Bool
	let profile: ColorThemeProfile

	init(
		id: String,
		label: String,
		appearance: ColorAppearance,
		codeTheme: String,
		uiFontFamily: String? = nil,
		codeFontFamily: String? = nil,
		contentFontFamily: String? = nil,
		opaqueWindows: Bool = false,
		background: UInt32,
		foreground: UInt32,
		accent: UInt32,
		contrast: Int,
		diffAdded: UInt32,
		diffRemoved: UInt32,
		skill: UInt32,
		namedAccent: ColorNamedAccent? = nil
	)
	{
		self.id = id
		self.label = label
		self.appearance = appearance
		self.codeTheme = codeTheme
		self.uiFontFamily = uiFontFamily
		self.codeFontFamily = codeFontFamily
		self.contentFontFamily = contentFontFamily
		self.opaqueWindows = opaqueWindows
		profile = ColorThemeProfile(
			background: background,
			foreground: foreground,
			accent: accent,
			contrast: contrast,
			diffAdded: diffAdded,
			diffRemoved: diffRemoved,
			skill: skill,
			namedAccent: namedAccent,
			presetID: id,
			codeThemeID: codeTheme,
			opaqueWindows: opaqueWindows,
			hasCustomFonts: uiFontFamily != nil || codeFontFamily != nil || contentFontFamily != nil
		)
	}
}

enum ColorThemePresets
{
	static let all: [ColorThemePreset] = [
		ColorThemePreset(
			id: "absolutely",
			label: "Absolutely",
			appearance: .dark,
			codeTheme: "Absolutely Dark",
			background: 0x2D2D2B,
			foreground: 0xF9F9F7,
			accent: 0xCC7D5E,
			contrast: 60,
			diffAdded: 0x00C853,
			diffRemoved: 0xFF5F38,
			skill: 0xCC7D5E
		),
		ColorThemePreset(
			id: "ayu",
			label: "Ayu",
			appearance: .dark,
			codeTheme: "ayu-dark",
			background: 0x10141C,
			foreground: 0xBFBDB6,
			accent: 0xE6B450,
			contrast: 60,
			diffAdded: 0x70BF56,
			diffRemoved: 0xF26D78,
			skill: 0xD0A1FF
		),
		ColorThemePreset(
			id: "catppuccin",
			label: "Catppuccin",
			appearance: .dark,
			codeTheme: "catppuccin-mocha",
			background: 0x1E1E2E,
			foreground: 0xCDD6F4,
			accent: 0xCBA6F7,
			contrast: 60,
			diffAdded: 0xA6E3A1,
			diffRemoved: 0xF38BA8,
			skill: 0xCBA6F7
		),
		ColorThemePreset(
			id: "codex",
			label: "Codex",
			appearance: .dark,
			codeTheme: "Codex Dark",
			background: 0x111111,
			foreground: 0xFCFCFC,
			accent: 0x0169CC,
			contrast: 60,
			diffAdded: 0x00A240,
			diffRemoved: 0xE02E2A,
			skill: 0xB06DFF,
			namedAccent: .default
		),
		ColorThemePreset(
			id: "dracula",
			label: "Dracula",
			appearance: .dark,
			codeTheme: "dracula",
			background: 0x282A36,
			foreground: 0xF8F8F2,
			accent: 0xFF79C6,
			contrast: 60,
			diffAdded: 0x50FA7B,
			diffRemoved: 0xFF5555,
			skill: 0xFF79C6
		),
		ColorThemePreset(
			id: "everforest",
			label: "Everforest",
			appearance: .dark,
			codeTheme: "everforest-dark",
			background: 0x2D353B,
			foreground: 0xD3C6AA,
			accent: 0xA7C080,
			contrast: 60,
			diffAdded: 0xA7C080,
			diffRemoved: 0xE67E80,
			skill: 0xD699B6
		),
		ColorThemePreset(
			id: "github",
			label: "GitHub",
			appearance: .dark,
			codeTheme: "github-dark-default",
			background: 0x0D1117,
			foreground: 0xE6EDF3,
			accent: 0x1F6FEB,
			contrast: 60,
			diffAdded: 0x3FB950,
			diffRemoved: 0xF85149,
			skill: 0xBC8CFF
		),
		ColorThemePreset(
			id: "gruvbox",
			label: "Gruvbox",
			appearance: .dark,
			codeTheme: "gruvbox-dark-medium",
			background: 0x282828,
			foreground: 0xEBDBB2,
			accent: 0x458588,
			contrast: 60,
			diffAdded: 0xEBDBB2,
			diffRemoved: 0xCC241D,
			skill: 0xB16286
		),
		ColorThemePreset(
			id: "linear",
			label: "Linear",
			appearance: .dark,
			codeTheme: "Linear Dark",
			uiFontFamily: "Inter",
			opaqueWindows: true,
			background: 0x0F0F11,
			foreground: 0xE3E4E6,
			accent: 0x606ACC,
			contrast: 60,
			diffAdded: 0x69C967,
			diffRemoved: 0xFF7E78,
			skill: 0xC2A1FF
		),
		ColorThemePreset(
			id: "lobster",
			label: "Lobster",
			appearance: .dark,
			codeTheme: "Lobster Dark",
			uiFontFamily: "Satoshi",
			background: 0x111827,
			foreground: 0xE4E4E7,
			accent: 0xFF5C5C,
			contrast: 60,
			diffAdded: 0x22C55E,
			diffRemoved: 0xFF5C5C,
			skill: 0x3B82F6
		),
		ColorThemePreset(
			id: "material",
			label: "Material",
			appearance: .dark,
			codeTheme: "material-theme-darker",
			background: 0x212121,
			foreground: 0xEEFFFF,
			accent: 0x80CBC4,
			contrast: 60,
			diffAdded: 0xC3E88D,
			diffRemoved: 0xF07178,
			skill: 0xC792EA
		),
		ColorThemePreset(
			id: "matrix",
			label: "Matrix",
			appearance: .dark,
			codeTheme: "Matrix Dark",
			uiFontFamily: "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, " +
				"Consolas, \"Liberation Mono\", monospace",
			opaqueWindows: true,
			background: 0x040805,
			foreground: 0xB8FFCA,
			accent: 0x1EFF5A,
			contrast: 60,
			diffAdded: 0x1EFF5A,
			diffRemoved: 0xFA423E,
			skill: 0x1EFF5A
		),
		ColorThemePreset(
			id: "monokai",
			label: "Monokai",
			appearance: .dark,
			codeTheme: "monokai",
			background: 0x272822,
			foreground: 0xF8F8F2,
			accent: 0x99947C,
			contrast: 60,
			diffAdded: 0x86B42B,
			diffRemoved: 0xC4265E,
			skill: 0x8C6BC8
		),
		ColorThemePreset(
			id: "night-owl",
			label: "Night Owl",
			appearance: .dark,
			codeTheme: "night-owl",
			background: 0x011627,
			foreground: 0xD6DEEB,
			accent: 0x44596B,
			contrast: 60,
			diffAdded: 0xC5E478,
			diffRemoved: 0xEF5350,
			skill: 0xC792EA
		),
		ColorThemePreset(
			id: "nord",
			label: "Nord",
			appearance: .dark,
			codeTheme: "nord",
			background: 0x2E3440,
			foreground: 0xD8DEE9,
			accent: 0x88C0D0,
			contrast: 60,
			diffAdded: 0xA3BE8C,
			diffRemoved: 0xBF616A,
			skill: 0xB48EAD
		),
		ColorThemePreset(
			id: "notion",
			label: "Notion",
			appearance: .dark,
			codeTheme: "Notion Dark",
			opaqueWindows: true,
			background: 0x191919,
			foreground: 0xD9D9D8,
			accent: 0x3183D8,
			contrast: 60,
			diffAdded: 0x4EC9B0,
			diffRemoved: 0xFA423E,
			skill: 0x3183D8
		),
		ColorThemePreset(
			id: "og",
			label: "OG",
			appearance: .dark,
			codeTheme: "OG Dark",
			uiFontFamily: "Arial, sans-serif",
			contentFontFamily: "Arial, sans-serif",
			opaqueWindows: true,
			background: 0x343541,
			foreground: 0xD1D5DB,
			accent: 0x10A37F,
			contrast: 60,
			diffAdded: 0x65C99A,
			diffRemoved: 0xF28B82,
			skill: 0xB4A1E5
		),
		ColorThemePreset(
			id: "one",
			label: "One",
			appearance: .dark,
			codeTheme: "one-dark-pro",
			background: 0x282C34,
			foreground: 0xABB2BF,
			accent: 0x4D78CC,
			contrast: 60,
			diffAdded: 0x8CC265,
			diffRemoved: 0xE05561,
			skill: 0xC162DE
		),
		ColorThemePreset(
			id: "oscurange",
			label: "Oscurange",
			appearance: .dark,
			codeTheme: "Oscurange",
			background: 0x0B0B0F,
			foreground: 0xE6E6E6,
			accent: 0xF9B98C,
			contrast: 60,
			diffAdded: 0x40C977,
			diffRemoved: 0xFA423E,
			skill: 0x479FFA
		),
		ColorThemePreset(
			id: "raycast",
			label: "Raycast",
			appearance: .dark,
			codeTheme: "Raycast Dark",
			uiFontFamily: "Inter",
			codeFontFamily: "\"Jetbrains Mono\"",
			background: 0x101010,
			foreground: 0xFEFEFE,
			accent: 0xFF6363,
			contrast: 60,
			diffAdded: 0x59D499,
			diffRemoved: 0xFF6363,
			skill: 0xCF2F98
		),
		ColorThemePreset(
			id: "rose-pine",
			label: "Rose Pine",
			appearance: .dark,
			codeTheme: "rose-pine-moon",
			background: 0x232136,
			foreground: 0xE0DEF4,
			accent: 0xEA9A97,
			contrast: 60,
			diffAdded: 0x9CCFD8,
			diffRemoved: 0x908CAA,
			skill: 0xC4A7E7
		),
		ColorThemePreset(
			id: "sentry",
			label: "Sentry",
			appearance: .dark,
			codeTheme: "Sentry Dark",
			background: 0x2D2935,
			foreground: 0xE6DFF9,
			accent: 0x7055F6,
			contrast: 60,
			diffAdded: 0x8EE6D7,
			diffRemoved: 0xFA423E,
			skill: 0x7055F6
		),
		ColorThemePreset(
			id: "solarized",
			label: "Solarized",
			appearance: .dark,
			codeTheme: "solarized-dark",
			background: 0x002B36,
			foreground: 0x839496,
			accent: 0xD30102,
			contrast: 60,
			diffAdded: 0x859900,
			diffRemoved: 0xDC322F,
			skill: 0xD33682
		),
		ColorThemePreset(
			id: "temple",
			label: "Temple",
			appearance: .dark,
			codeTheme: "Temple Dark",
			background: 0x02120C,
			foreground: 0xC7E6DA,
			accent: 0xE4F222,
			contrast: 60,
			diffAdded: 0x40C977,
			diffRemoved: 0xFA423E,
			skill: 0xE4F222
		),
		ColorThemePreset(
			id: "tokyo-night",
			label: "Tokyo Night",
			appearance: .dark,
			codeTheme: "tokyo-night",
			background: 0x1A1B26,
			foreground: 0xA9B1D6,
			accent: 0x3D59A1,
			contrast: 60,
			diffAdded: 0x449DAB,
			diffRemoved: 0x914C54,
			skill: 0x9D7CD8
		),
		ColorThemePreset(
			id: "vercel",
			label: "Vercel",
			appearance: .dark,
			codeTheme: "Vercel Dark",
			uiFontFamily: "Geist, Inter",
			codeFontFamily: "\"Geist Mono\", ui-monospace, \"SFMono-Regular\"",
			opaqueWindows: true,
			background: 0x000000,
			foreground: 0xEDEDED,
			accent: 0x006EFE,
			contrast: 50,
			diffAdded: 0x00AD3A,
			diffRemoved: 0xF13342,
			skill: 0x9540D5
		),
		ColorThemePreset(
			id: "vscode-plus",
			label: "VS Code Plus",
			appearance: .dark,
			codeTheme: "dark-plus",
			background: 0x1E1E1E,
			foreground: 0xD4D4D4,
			accent: 0x007ACC,
			contrast: 60,
			diffAdded: 0x369432,
			diffRemoved: 0xF44747,
			skill: 0x000080
		),
		ColorThemePreset(
			id: "xcode",
			label: "Xcode",
			appearance: .dark,
			codeTheme: "Xcode Dark",
			codeFontFamily: "\"SFMono-Medium\"",
			background: 0x1F1F24,
			foreground: 0xFFFFFF,
			accent: 0x5482FF,
			contrast: 60,
			diffAdded: 0x67B7A4,
			diffRemoved: 0xFC6A5D,
			skill: 0x5482FF
		),
		ColorThemePreset(
			id: "absolutely",
			label: "Absolutely",
			appearance: .light,
			codeTheme: "Absolutely Light",
			background: 0xF9F9F7,
			foreground: 0x2D2D2B,
			accent: 0xCC7D5E,
			contrast: 45,
			diffAdded: 0x00C853,
			diffRemoved: 0xFF5F38,
			skill: 0xCC7D5E
		),
		ColorThemePreset(
			id: "catppuccin",
			label: "Catppuccin",
			appearance: .light,
			codeTheme: "catppuccin-latte",
			background: 0xEFF1F5,
			foreground: 0x4C4F69,
			accent: 0x8839EF,
			contrast: 45,
			diffAdded: 0x40A02B,
			diffRemoved: 0xD20F39,
			skill: 0x8839EF
		),
		ColorThemePreset(
			id: "codex",
			label: "Codex",
			appearance: .light,
			codeTheme: "Codex Light",
			background: 0xFFFFFF,
			foreground: 0x0D0D0D,
			accent: 0x0169CC,
			contrast: 45,
			diffAdded: 0x00A240,
			diffRemoved: 0xE02E2A,
			skill: 0x751ED9,
			namedAccent: .default
		),
		ColorThemePreset(
			id: "everforest",
			label: "Everforest",
			appearance: .light,
			codeTheme: "everforest-light",
			background: 0xFDF6E3,
			foreground: 0x5C6A72,
			accent: 0x93B259,
			contrast: 45,
			diffAdded: 0x8DA101,
			diffRemoved: 0xF85552,
			skill: 0xDF69BA
		),
		ColorThemePreset(
			id: "github",
			label: "GitHub",
			appearance: .light,
			codeTheme: "github-light-default",
			background: 0xFFFFFF,
			foreground: 0x1F2328,
			accent: 0x0969DA,
			contrast: 45,
			diffAdded: 0x1A7F37,
			diffRemoved: 0xCF222E,
			skill: 0x8250DF
		),
		ColorThemePreset(
			id: "gruvbox",
			label: "Gruvbox",
			appearance: .light,
			codeTheme: "gruvbox-light-medium",
			background: 0xFBF1C7,
			foreground: 0x3C3836,
			accent: 0x458588,
			contrast: 45,
			diffAdded: 0x3C3836,
			diffRemoved: 0xCC241D,
			skill: 0xB16286
		),
		ColorThemePreset(
			id: "linear",
			label: "Linear",
			appearance: .light,
			codeTheme: "Linear Light",
			uiFontFamily: "Inter",
			opaqueWindows: true,
			background: 0xFCFCFD,
			foreground: 0x1B1B1B,
			accent: 0x5E6AD2,
			contrast: 45,
			diffAdded: 0x52A450,
			diffRemoved: 0xC94446,
			skill: 0x8160D8
		),
		ColorThemePreset(
			id: "notion",
			label: "Notion",
			appearance: .light,
			codeTheme: "Notion Light",
			opaqueWindows: true,
			background: 0xFFFFFF,
			foreground: 0x37352F,
			accent: 0x3183D8,
			contrast: 45,
			diffAdded: 0x008000,
			diffRemoved: 0xA31515,
			skill: 0x0000FF
		),
		ColorThemePreset(
			id: "one",
			label: "One",
			appearance: .light,
			codeTheme: "one-light",
			background: 0xFAFAFA,
			foreground: 0x383A42,
			accent: 0x526FFF,
			contrast: 45,
			diffAdded: 0x3BBA54,
			diffRemoved: 0xE45649,
			skill: 0x526FFF
		),
		ColorThemePreset(
			id: "proof",
			label: "Proof",
			appearance: .light,
			codeTheme: "Proof Light",
			background: 0xF5F3ED,
			foreground: 0x2F312D,
			accent: 0x3D755D,
			contrast: 45,
			diffAdded: 0x3D755D,
			diffRemoved: 0xBA2623,
			skill: 0x5F6AC2
		),
		ColorThemePreset(
			id: "raycast",
			label: "Raycast",
			appearance: .light,
			codeTheme: "Raycast Light",
			uiFontFamily: "Inter",
			codeFontFamily: "\"Jetbrains Mono\"",
			background: 0xFFFFFF,
			foreground: 0x030303,
			accent: 0xFF6363,
			contrast: 45,
			diffAdded: 0x006B4F,
			diffRemoved: 0xB12424,
			skill: 0x9A1B6E
		),
		ColorThemePreset(
			id: "rose-pine",
			label: "Rose Pine",
			appearance: .light,
			codeTheme: "rose-pine-dawn",
			background: 0xFAF4ED,
			foreground: 0x575279,
			accent: 0xD7827E,
			contrast: 45,
			diffAdded: 0x56949F,
			diffRemoved: 0x797593,
			skill: 0x907AA9
		),
		ColorThemePreset(
			id: "solarized",
			label: "Solarized",
			appearance: .light,
			codeTheme: "solarized-light",
			background: 0xFDF6E3,
			foreground: 0x657B83,
			accent: 0xB58900,
			contrast: 45,
			diffAdded: 0x859900,
			diffRemoved: 0xDC322F,
			skill: 0xD33682
		),
		ColorThemePreset(
			id: "vercel",
			label: "Vercel",
			appearance: .light,
			codeTheme: "Vercel Light",
			uiFontFamily: "Geist, Inter",
			codeFontFamily: "\"Geist Mono\", ui-monospace, \"SFMono-Regular\"",
			opaqueWindows: true,
			background: 0xFFFFFF,
			foreground: 0x171717,
			accent: 0x006AFF,
			contrast: 40,
			diffAdded: 0x28A948,
			diffRemoved: 0xEB001D,
			skill: 0xA100F8
		),
		ColorThemePreset(
			id: "vscode-plus",
			label: "VS Code Plus",
			appearance: .light,
			codeTheme: "light-plus",
			background: 0xFFFFFF,
			foreground: 0x000000,
			accent: 0x007ACC,
			contrast: 45,
			diffAdded: 0x008000,
			diffRemoved: 0xEE0000,
			skill: 0x0000FF
		),
		ColorThemePreset(
			id: "xcode",
			label: "Xcode",
			appearance: .light,
			codeTheme: "Xcode Light",
			codeFontFamily: "\"SFMono-Regular\"",
			background: 0xFFFFFF,
			foreground: 0x000000,
			accent: 0x0E0EFF,
			contrast: 45,
			diffAdded: 0x00A240,
			diffRemoved: 0xC41A16,
			skill: 0x0E0EFF
		),
	]

	static func preset(
		id: String,
		appearance: ColorAppearance
	) -> ColorThemePreset?
	{
		all.first
		{
			$0.id == id && $0.appearance == appearance
		}
	}
}
