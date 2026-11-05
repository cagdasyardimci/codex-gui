import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct TypographyConsumerRefreshTests
{
	@Test func keycapRefreshFitsTextAndPreservesItsAction()
	{
		_ = NSApplication.shared
		let center = NotificationCenter()
		let state = ConfigurationState()
		let target = ActionTarget()
		let button = DesktopKeycapButton(
			title: "Escape",
			target: target,
			action: #selector(ActionTarget.activate),
			configuration:
			{
				state.value
			},
			center: center
		)
		let originalWidth = button.fittingSize.width
		state.value = TypographyConfiguration(uiSize: 16)
		center.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		#expect(button.font?.pointSize == 15)
		#expect(button.fittingSize.width > originalWidth)
		#expect(button.fittingSize.width >= (button.title as NSString)
			.size(withAttributes: [.font: button.font!]).width)
		#expect(button.sendAction(
			button.action,
			to: button.target
		))
		#expect(target.activations == 1)
		state.value = TypographyConfiguration(uiSize: 11)
		center.post(
			name: TypographyPreferences.didChange,
			object: nil
		)
		#expect(button.fittingSize.width < originalWidth)
		#expect(button.title == "Escape")
	}

	@Test func richTextRefreshPreservesLinkAndSelection() throws
	{
		let center = NotificationCenter()
		let state = ConfigurationState()
		let text = NSTextView()
		let link = URL(string: "https://example.com/help")!
		text.textStorage?.setAttributedString(NSAttributedString(
			string: "Read help",
			attributes: [.link: link]
		))
		text.setSelectedRange(NSRange(
			location: 5,
			length: 4
		))
		text.setTypographyRole(
			TypographyTokens.Dialog.body,
			configuration:
			{
				state.value
			},
			center: center
		)
		for size: CGFloat in [16, 11]
		{
			state.value = TypographyConfiguration(uiSize: size)
			center.post(
				name: TypographyPreferences.didChange,
				object: nil
			)
			let storage = try #require(text.textStorage)
			#expect((storage.attribute(
				.font,
				at: 5,
				effectiveRange: nil
			) as? NSFont)?
				.pointSize == size)
			#expect(storage.attribute(
				.link,
				at: 5,
				effectiveRange: nil
			) as? URL == link)
			#expect(text.selectedRange() == NSRange(
				location: 5,
				length: 4
			))
			#expect((storage.attribute(
				.paragraphStyle,
				at: 5,
				effectiveRange: nil
			) as? NSParagraphStyle)?.lineSpacing == 3)
			#expect(text.string == "Read help")
		}
	}

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

	@Test(.appKitIsolation) func preparedDiagramsRefreshTheirFontsWithoutReusingOldVectors(
	) async throws
	{
		let parsed = MarkdownContentParser.parse(
			"```mermaid\nflowchart LR\nA[Typography] --> B[Refresh]\n```",
			markdown: true
		)
		let preset = try #require(ColorThemePresets.preset(
			id: "og",
			appearance: .dark
		))
		let colors = ColorThemeConfiguration(dark: preset.profile)
		var vectors: [Data] = []
		var sizes: [NSSize] = []
		for size: CGFloat in [11, 16]
		{
			let images = await MarkdownMermaidRenderer.prepare(
				parsed: parsed,
				typography: TypographyConfiguration(uiSize: size),
				colorTheme: colors
			)
			let image = try #require(images.values.first?.dark as? MarkdownSVGImage)
			let markup = try #require(String(
				data: image.svgData,
				encoding: .utf8
			))
			#expect(markup.contains("Arial"))
			#expect(markup.contains("font-size:" + String(Int(size)) + "px") ||
				markup.contains("font-size: " + String(Int(size)) + "px"))
			vectors.append(image.svgData)
			sizes.append(image.size)
		}
		#expect(vectors[0] != vectors[1])
		#expect(sizes[0] == sizes[1])
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
