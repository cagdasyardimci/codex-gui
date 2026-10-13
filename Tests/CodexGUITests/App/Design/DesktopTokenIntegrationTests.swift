import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct DesktopTokenIntegrationTests
{
	@Test func sharedControlStylesKeepTheExistingNativeFonts()
	{
		let button = NSButton(
			title: "Action",
			target: nil,
			action: nil
		)
		AppKitControlStyling.styleButton(button)
		#expect(button.font == NSFont.systemFont(ofSize: 12))
		AppKitControlStyling.styleButton(
			button,
			prominent: true
		)
		#expect(button.font == NSFont.systemFont(
			ofSize: 12,
			weight: .medium
		))
		#expect(AppKitControlStyling.sectionLabel("Section").font
			== NSFont.systemFont(
				ofSize: 11,
				weight: .medium
			))
	}

	@Test func extractedSurfaceKeepsNativeOpacityBehavior()
	{
		let flat = DesktopSurface(.white)
		let rounded = DesktopSurface(
			.white,
			cornerRadius: 16
		)
		#expect(flat.isOpaque)
		#expect(!rounded.isOpaque)
	}

	@Test func existingDynamicPaletteResolvesUnderTheOwningAppearance() throws
	{
		let owner = NSView()
		owner.appearance = NSAppearance(named: .darkAqua)
		let resolved = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.userBubble,
			for: owner
		)
		let color = try #require(NSColor(cgColor: resolved)?.usingColorSpace(.sRGB))
		#expect(abs(color.redComponent - 34 / 255.0) < 0.001)
		#expect(abs(color.greenComponent - 61 / 255.0) < 0.001)
		#expect(abs(color.blueComponent - 114 / 255.0) < 0.001)
	}
}
