import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ThemeConsumerColorTests
{
	@Test(arguments: [ColorAppearance.light, .dark])
	func contrastPairsStayLegibleOnCustomSurfaces(_ mode: ColorAppearance)
	{
		let palette = ColorPalette(
			configuration: ColorThemeProfile(
				background: mode == .dark ? 0x102030 : 0xEEE5D5,
				foreground: mode == .dark ? 0xE0E8F0 : 0x302010,
				accent: 0xCCAA55,
				contrast: 60
			),
			mode: mode
		)
		for (foreground, surface) in [
			(palette.tooltipText, palette.tooltipCapsule),
			(palette.qrInk, palette.qrSurface),
			(palette.avatarText, palette.accentBackground),
			(palette.switchThumb(on: true), palette.accent),
			(palette.switchThumb(on: false), palette.surface)
		]
		{
			#expect(contrast(
				foreground,
				surface
			) >= 4.5)
			#expect(surface.alphaComponent == 1)
		}
	}

	@Test func selectedCodeThemeRecolorsBothSourceAndMarkdownWithoutLosingBytes() throws
	{
		let source = "const value = 42; // 😄\r\n"
		var colors: [NSColor] = []
		for id in ["ayu-dark", "Lobster Dark", "ayu-dark"]
		{
			let configuration = ColorThemeConfiguration(dark: ColorThemeProfile(
				background: 0x102030,
				foreground: 0xE0E8F0,
				accent: 0xCCAA55,
				contrast: 60,
				codeThemeID: id
			))
			let normal = try #require(CodeSyntaxHighlighter.highlightedCode(
				source,
				language: "javascript",
				dark: true,
				configuration: configuration
			))
			let markdown = try #require(CodeSyntaxHighlighter.highlightedCode(
				source,
				language: "javascript",
				dark: true,
				usePreset: false,
				configuration: configuration
			))
			#expect(Data(normal.string.utf8) == Data(source.utf8))
			#expect(Data(markdown.string.utf8) == Data(source.utf8))
			let offset = (source as NSString).range(of: "42").location
			let normalColor = try #require(normal.attribute(
				.foregroundColor,
				at: offset,
				effectiveRange: nil
			) as? NSColor)
			let markdownColor = try #require(markdown.attribute(
				.foregroundColor,
				at: offset,
				effectiveRange: nil
			) as? NSColor)
			#expect(normalColor == markdownColor)
			colors.append(normalColor)
		}
		#expect(colors[0] != colors[1])
		#expect(colors[0] == colors[2])
	}

	@Test(.appKitIsolation) func retainedSearchSurfaceRefreshesWithoutReplacingInputs() throws
	{
		let query = NSTextField(string: "draft query")
		let mask = NSTextField(string: "*.swift")
		let panel = DesktopFileSearchContentView(
			mode: .content,
			queryField: query,
			maskField: mask,
			maskLabel: NSTextField(labelWithString: "Types"),
			escapeButton: NSButton(),
			keyboardHints: NSView(),
			table: NSTableView()
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 400
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = panel
		defer
		{
			window.close()
		}
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			panel.layer?.backgroundColor = NSColor.magenta.cgColor
			NotificationCenter.default.post(
				name: ColorPreferences.didChange,
				object: nil
			)
			#expect(panel.layer?.backgroundColor == AppKitColorResolution.resolvedCGColor(
				AppKitColorTokens.editorSurface,
				for: panel
			))
			#expect(query.stringValue == "draft query")
			#expect(mask.stringValue == "*.swift")
		}
	}

	@Test(.appKitIsolation) func mermaidUsesProfileColorsAndInvalidatesPreparedVectors(
	) async throws
	{
		let source = "```mermaid\nflowchart LR\nA[Theme] --> B[Refresh]\n```"
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		var vectors: [Data] = []
		for accent: UInt32 in [0xFF5566, 0x55DD88]
		{
			let configuration = ColorThemeConfiguration(dark: ColorThemeProfile(
				background: 0x102030,
				foreground: 0xE0E8F0,
				accent: accent,
				contrast: 60
			))
			let images = await MarkdownMermaidRenderer.prepare(
				parsed: parsed,
				colorTheme: configuration
			)
			let image = try #require(images.values.first?.dark as? MarkdownSVGImage)
			let markup = try #require(String(
				data: image.svgData,
				encoding: .utf8
			))
			let colors = AppKitColorTokens.richContentColors(
				appearance: NSAppearance(named: .darkAqua)!,
				configuration: configuration
			)
			let ink = try #require(colors["ink"])
			#expect(markup.contains(ink))
			vectors.append(image.svgData)
		}
		#expect(vectors[0] != vectors[1])
	}

	private func contrast(
		_ first: NSColor,
		_ second: NSColor
	) -> CGFloat
	{
		func luminance(_ color: NSColor) -> CGFloat
		{
			let c = color.usingColorSpace(.sRGB)!
			func linear(_ x: CGFloat) -> CGFloat
			{
				x <= 0.04045 ? x / 12.92 : pow(
					(x + 0.055) / 1.055,
					2.4
				)
			}
			return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 *
				linear(c.blueComponent)
		}
		let a = luminance(first), b = luminance(second)
		return (max(
			a,
			b
		) + 0.05) / (min(
			a,
			b
		) + 0.05)
	}
}
