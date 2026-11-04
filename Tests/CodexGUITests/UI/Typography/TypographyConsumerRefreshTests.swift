import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct TypographyConsumerRefreshTests
{

	@Test func diagramArgumentsUseUIFamilyAndIndependentNodeMetrics()
	{
		let profile = ColorThemeProfile(
			background: 0x111111,
			foreground: 0xFCFCFC,
			accent: 0x0169CC,
			contrast: 60,
			uiFontFamily: "Arial",
			contentFontFamily: "Times New Roman"
		)
		let arguments = AppKitFontResolver.diagramTypography(
			appearance: NSAppearance(named: .darkAqua)!,
			configuration: TypographyConfiguration(
				uiSize: 16,
				codeSize: 24
			),
			colorConfiguration: ColorThemeConfiguration(dark: profile)
		)
		#expect(arguments["fontFamily"] as? String == "\"Arial\"")
		#expect(arguments["bodySize"] as? CGFloat == 16)
		#expect(arguments["edgeSize"] as? CGFloat == 15)
		#expect(arguments["nodeSize"] as? CGFloat == 14)
		#expect(arguments["nodeWeight"] as? Int == 600)
	}

}

@MainActor
private final class ConfigurationState
{
	var value = TypographyConfiguration.standard
}

@MainActor
private final class ActionTarget: NSObject
{
	var activations = 0
	@objc func activate()
	{
		activations += 1
	}
}
