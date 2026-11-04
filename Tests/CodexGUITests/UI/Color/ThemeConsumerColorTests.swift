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
