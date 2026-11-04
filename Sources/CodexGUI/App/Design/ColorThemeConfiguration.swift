import Foundation

enum ColorThemeMode: String, Codable, CaseIterable, Hashable, Sendable
{
	case system, light, dark
}

enum ColorAppearance: String, Codable, Hashable, Sendable
{
	case light, dark
}

enum ColorNamedAccent: String, Codable, CaseIterable, Hashable, Sendable
{
	case `default`, blue, green, yellow, pink, orange, purple, black
}

struct ColorThemeProfile: Codable, Hashable, Sendable
{
	let background: UInt32
	let foreground: UInt32
	let accent: UInt32
	let contrast: Int
	let diffAdded: UInt32
	let diffRemoved: UInt32
	let skill: UInt32
	let namedAccent: ColorNamedAccent?
	let colorizeMessages: Bool
	let presetID: String?
	let codeThemeID: String?
	let opaqueWindows: Bool
	let hasCustomFonts: Bool
	let uiFontFamily: String?
	let contentFontFamily: String?
	let codeFontFamily: String?

	private enum CodingKeys: String, CodingKey
	{
		case background, foreground, accent, contrast, diffAdded, diffRemoved, skill, namedAccent,
				colorizeMessages, presetID, codeThemeID, opaqueWindows, hasCustomFonts,
				uiFontFamily, contentFontFamily, codeFontFamily
	}

	init(from decoder: Decoder) throws
	{
		let values = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			background: try values.decode(
				UInt32.self,
				forKey: .background
			),
			foreground: try values.decode(
				UInt32.self,
				forKey: .foreground
			),
			accent: try values.decode(
				UInt32.self,
				forKey: .accent
			),
			contrast: try values.decode(
				Int.self,
				forKey: .contrast
			),
			diffAdded: try values.decodeIfPresent(
				UInt32.self,
				forKey: .diffAdded
			) ?? 0x00A240,
			diffRemoved: try values.decodeIfPresent(
				UInt32.self,
				forKey: .diffRemoved
			) ?? 0xE02E2A,
			skill: try values.decodeIfPresent(
				UInt32.self,
				forKey: .skill
			) ?? 0xB06DFF,
			namedAccent: try values.decodeIfPresent(
				ColorNamedAccent.self,
				forKey: .namedAccent
			),
			colorizeMessages: try values
				.decodeIfPresent(
					Bool.self,
					forKey: .colorizeMessages
				) ?? true,
			presetID: try values.decodeIfPresent(
				String.self,
				forKey: .presetID
			),
			codeThemeID: try values.decodeIfPresent(
				String.self,
				forKey: .codeThemeID
			),
			opaqueWindows: try values.decodeIfPresent(
				Bool.self,
				forKey: .opaqueWindows
			) ?? false,
			hasCustomFonts: try values.decodeIfPresent(
				Bool.self,
				forKey: .hasCustomFonts
			) ?? false,
			uiFontFamily: try values.decodeIfPresent(
				String.self,
				forKey: .uiFontFamily
			),
			contentFontFamily: try values.decodeIfPresent(
				String.self,
				forKey: .contentFontFamily
			),
			codeFontFamily: try values.decodeIfPresent(
				String.self,
				forKey: .codeFontFamily
			)
		)
	}

	init(
		background: UInt32,
		foreground: UInt32,
		accent: UInt32,
		contrast: Int,
		diffAdded: UInt32 = 0x00A240,
		diffRemoved: UInt32 = 0xE02E2A,
		skill: UInt32 = 0xB06DFF,
		namedAccent: ColorNamedAccent? = nil,
		colorizeMessages: Bool = true,
		presetID: String? = nil,
		codeThemeID: String? = nil,
		opaqueWindows: Bool = false,
		hasCustomFonts: Bool = false,
		uiFontFamily: String? = nil,
		contentFontFamily: String? = nil,
		codeFontFamily: String? = nil
	)
	{
		self.background = background & 0xFFFFFF
		self.foreground = foreground & 0xFFFFFF
		self.accent = accent & 0xFFFFFF
		self.contrast = min(
			100,
			max(
				0,
				contrast
			)
		)
		self.diffAdded = diffAdded & 0xFFFFFF
		self.diffRemoved = diffRemoved & 0xFFFFFF
		self.skill = skill & 0xFFFFFF
		self.namedAccent = namedAccent
		self.colorizeMessages = colorizeMessages
		self.presetID = presetID
		self.codeThemeID = codeThemeID
		self.opaqueWindows = opaqueWindows
		self.hasCustomFonts = hasCustomFonts
		self.uiFontFamily = uiFontFamily
		self.contentFontFamily = contentFontFamily
		self.codeFontFamily = codeFontFamily
	}

	static let light = ColorThemeProfile(
		background: 0xFFFFFF,
		foreground: 0x0D0D0D,
		accent: 0x0169CC,
		contrast: 45,
		skill: 0x751ED9
	)
	static let dark = ColorThemeProfile(
		background: 0x111111,
		foreground: 0xFCFCFC,
		accent: 0x3A83F7,
		contrast: 60
	)
}

struct ColorThemeConfiguration: Codable, Hashable, Sendable
{
	let light: ColorThemeProfile
	let dark: ColorThemeProfile
	let mode: ColorThemeMode

	init(
		light: ColorThemeProfile = .light,
		dark: ColorThemeProfile = .dark,
		mode: ColorThemeMode = .system
	)
	{
		self.light = light
		self.dark = dark
		self.mode = mode
	}

	func profile(for appearance: ColorAppearance) -> ColorThemeProfile
	{
		appearance == .dark ? dark : light
	}
}
