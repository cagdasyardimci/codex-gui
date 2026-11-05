import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct GitDiffThemeColorsTests
{
	@Test func selectedDiffUsesConfiguredAccentAndDistinctGutterEmphasis() throws
	{
		let base = NSColor(
			srgbRed: 0.15,
			green: 0.12,
			blue: 0.16,
			alpha: 1
		)
		func palette(_ accent: UInt32) -> ColorPalette
		{
			ColorPalette(
				configuration: ColorThemeProfile(
					background: 0x111827,
					foreground: 0xE4E4E7,
					accent: accent,
					contrast: 60
				),
				mode: .dark
			)
		}
		let red = palette(0xFF5C5C)
		let green = palette(0x22C55E)
		let selected = red.diffSelection(
			over: base,
			gutter: false
		)
		#expect(selected != base)
		#expect(selected != green.diffSelection(
			over: base,
			gutter: false
		))
		#expect(selected != red.diffSelection(
			over: base,
			gutter: true
		))
		#expect(selected.alphaComponent == 1)
	}

	@Test(arguments: [
		(UInt32(0x22C55E), [29.0, 54.0, 51.0]),
		(UInt32(0xFF5C5C), [63.0, 39.0, 49.0]),
	])
	func contentMixMatchesMeasuredReference(
		_ semantic: UInt32,
		expected: [Double]
	) throws
	{
		func color(_ hex: UInt32) -> NSColor
		{
			NSColor(
				srgbRed: CGFloat((hex >> 16) & 255) / 255,
				green: CGFloat((hex >> 8) & 255) / 255,
				blue: CGFloat(hex & 255) / 255,
				alpha: 1
			)
		}
		let result = try #require(GitDiffThemeColors.labMix(
			color(0x111827),
			color(semantic),
			amount: 0.2
		).usingColorSpace(.sRGB))
		let channels = [result.redComponent, result.greenComponent, result.blueComponent]
		for (actual, value) in zip(
			channels,
			expected
		)
		{
			#expect(abs(Double(actual) * 255 - value) < 1)
		}
	}
}
