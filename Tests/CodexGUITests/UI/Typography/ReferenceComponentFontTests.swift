import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ReferenceComponentFontTests
{
	@Test(arguments: [
		TypographyConfiguration(
			uiSize: 11,
			codeSize: 12
		),
		TypographyConfiguration(
			uiSize: 13,
			codeSize: 12
		),
		TypographyConfiguration(
			uiSize: 14,
			codeSize: 12
		),
		TypographyConfiguration(
			uiSize: 16,
			codeSize: 12
		),
		TypographyConfiguration(
			uiSize: 14,
			codeSize: 16
		),
	])
	func correctedComponentsFollowTheirMeasuredUIRules(_ config: TypographyConfiguration)
	{
		#expect(TypographyTokens.Settings.sidebarRow.resolved(using: config).size == config.uiSize)
		#expect(TypographyTokens.Settings.sidebarRow.weight == .regular)
		#expect(TypographyTokens.Search.section.resolved(using: config).size == config.uiSize - 1)
		#expect(TypographyTokens.Search.section.weight == .text)
		let terminal = AppKitFontResolver.font(
			TypographyTokens.Terminal.text,
			configuration: config
		)
		#expect(terminal.fontName == "Menlo-Regular")
		#expect(terminal.pointSize == config.uiSize - 1)
		#expect(TypographyTokens.Code.source.resolved(using: config).size == config.codeSize)
	}

	@Test func settingsTitleUsesProvidedFaceAndRetainsHeadingScaling()
	{
		let library = FileManager.default.urls(
			for: .libraryDirectory,
			in: .userDomainMask
		).first
		let provided = library.map
		{
			FileManager.default
				.fileExists(atPath: $0.appendingPathComponent("Fonts/OpenAISans-Semibold.woff2")
					.path)
		} == true || NSFont(
			name: "OpenAISans-Semibold",
			size: 18
		) != nil
		for (ui, expected): (CGFloat, CGFloat) in [(13, 17), (14, 18), (16, 21)]
		{
			let font = AppKitFontResolver.font(
				TypographyTokens.Settings.heading,
				configuration: TypographyConfiguration(uiSize: ui)
			)
			#expect(font.pointSize == expected)
			if provided
			{
				#expect(font.fontName == "OpenAISans-Semibold")
			}
			else
			{
				#expect(font.fontName.hasPrefix(".SFNS"))
			}
		}
	}

	@Test func quickActionsSectionUsesCorrectedRole() throws
	{
		let section = DesktopSearchOverlayView.message(
			"Quick actions",
			presentation: .section
		)
		let label = try #require(descendants(section).compactMap
		{
			$0 as? NSTextField
		}.first)
		#expect(label.font?.pointSize == TypographyConfiguration.current.uiSize - 1)
		#expect(label.stringValue == "Quick actions")
	}

	@Test func expandedShellUsesCorrectedRoleInActualTextStorage() throws
	{
		let card = ConversationTerminalCard()
		card.configure(
			ConversationCommand(
				command: "printf 'font fixture'",
				cwd: "/tmp",
				output: "font fixture",
				status: "completed",
				exitCode: 0,
				durationMs: 1,
				actions: []
			),
			expanded: true,
			preserving: nil
		)
		let output = try #require(descendants(card).compactMap
		{
			$0 as? NSTextView
		}.first)
		let font = try #require(output.textStorage?.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)
		#expect(font.fontName == "Menlo-Regular")
		#expect(font.pointSize == TypographyConfiguration.current.uiSize - 1)
		let paragraph = try #require(output.textStorage?.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		#expect(paragraph.minimumLineHeight == (TypographyConfiguration.current.uiSize - 1) * 1.5)
		let foreground = try #require(output.textStorage?.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) as? NSColor)
		#expect(foreground.alphaComponent == 0.7)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
