import Testing
@testable import CodexGUI

@Suite
struct ColorThemePresetsTests
{
	@Test func lookupPreservesMeasuredProfileAndModeAvailability() throws
	{
		let lobster = try #require(ColorThemePresets.preset(
			id: "lobster",
			appearance: .dark
		))
		#expect(lobster.profile.background == 0x111827)
		#expect(lobster.profile.foreground == 0xE4E4E7)
		#expect(lobster.profile.accent == 0xFF5C5C)
		#expect(lobster.profile.diffAdded == 0x22C55E)
		#expect(lobster.profile.codeThemeID == "Lobster Dark")
		#expect(lobster.profile.hasCustomFonts)
		#expect(ColorThemePresets.preset(
			id: "lobster",
			appearance: .light
		)?.id == nil)
	}

	@Test func presetCarriesSourceAndRendererMetadata() throws
	{
		let codex = try #require(ColorThemePresets.preset(
			id: "codex",
			appearance: .dark
		))
		#expect(codex.profile.namedAccent == .default)
		#expect(codex.profile.presetID == "codex")
		let vercel = try #require(ColorThemePresets.preset(
			id: "vercel",
			appearance: .light
		))
		#expect(vercel.profile.contrast == 40)
		#expect(vercel.profile.opaqueWindows)
		#expect(vercel.codeFontFamily != nil)
	}
}
