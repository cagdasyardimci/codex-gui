import AppKit
import CoreText
import Testing

@testable import CodexGUI

@MainActor
struct DesktopTextEntryPromptTests
{
	@Test func dialogTypographyRetainsItsRowsAtTheLargestUISize() throws
	{
		let configuration = TypographyConfiguration(uiSize: 16)
		let title = AppKitFontResolver.textAttributes(
			TypographyTokens.Dialog.title,
			configuration: configuration
		)
		let action = AppKitFontResolver.textAttributes(
			TypographyTokens.Dialog.action,
			configuration: configuration
		)
		#expect((title[.font] as? NSFont)?.pointSize == 23)
		#expect((title[.paragraphStyle] as? NSParagraphStyle)?.minimumLineHeight == 28)
		#expect((action[.paragraphStyle] as? NSParagraphStyle)?.minimumLineHeight == 18)
		#expect((action[.paragraphStyle] as? NSParagraphStyle)?.maximumLineHeight == 18)
	}
	@Test func textEntryCompositionUsesTheSharedFieldAndReferenceGeometry() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let prompt = DesktopTextEntryPrompt(
				title: "Rename chat",
				detail: "Keep it short and recognizable",
				actionTitle: "Save",
				fields: [.init(
					value: "Fixture",
					placeholder: nil,
					accessibilityLabel: "Chat title"
				)],
				layout: .single
			)
			let field = try #require(prompt.fields.first)
			let panel = try #require(field.window)
			defer
			{
				panel.close()
			}
			let shell = try #require(panel.contentView as? DesktopDialogShell)
			shell.layoutSubtreeIfNeeded()
			#expect(field is SettingsFormTextField)
			#expect(field.frame.size == NSSize(
				width: 380,
				height: 36
			))
			#expect(panel.frame.size == NSSize(
				width: 420,
				height: 185
			))
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [
			(UInt16(36), ""),
			(36, "   "),
			(36, "  Edited name  "),
			(76, "  Edited name  "),
			(53, "  Edited name  ")
		]
	)
	func routedKeysKeepEditedValueAndCompleteOnlyOnce(sample: (UInt16, String)) async throws
	{
		let keyCode = sample.0
		try await AppKitTestIsolation.perform
		{
			let parent = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 800,
					height: 600
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			parent.prepareForTesting()
			defer
			{
				parent.close()
			}
			let prompt = DesktopTextEntryPrompt(
				title: "Rename Conversation",
				actionTitle: "Rename",
				fields: [.init(
					value: "Original",
					placeholder: "Name",
					accessibilityLabel: "Name"
				)],
				layout: .single
			)
			let result = AsyncStream<[String]?>.makeStream()
			prompt.beginSheet(in: parent)
			{
				values in
				result.continuation.yield(values)
				result.continuation.finish()
			}
			let sheet = try #require(parent.attachedSheet)
			sheet.prepareForTesting()
			let shell = try #require(sheet.contentView as? DesktopDialogShell)
			let ui = TypographyConfiguration.current.uiSize
			try expectFont(
				shell.titleLabel.font,
				size: TypographyConfiguration.current.heading(20),
				weight: 600
			)
			try expectFont(
				prompt.fields[0].font,
				size: ui - 1,
				weight: 430
			)
			let buttons = descendants(shell.actionsRow).compactMap
			{
				$0 as? NSButton
			}
			#expect(buttons.map(\.title) == ["Cancel", "Rename"])
			for button in buttons
			{
				try expectFont(
					button.font,
					size: ui,
					weight: 430
				)
			}
			let editor = try #require(prompt.fields[0].currentEditor() as? NSTextView)
			let selection = try #require(editor
				.selectedTextAttributes[.backgroundColor] as? NSColor)
			let expectedSelection = AppKitColorTokens.paletteColor
			{
				$0.selectionBackground
			}
			var actualColor: NSColor?
			var expectedColor: NSColor?
			sheet.effectiveAppearance.performAsCurrentDrawingAppearance
			{
				actualColor = selection.usingColorSpace(.sRGB)
				expectedColor = expectedSelection.usingColorSpace(.sRGB)
			}
			let actual = try #require(actualColor)
			let expected = try #require(expectedColor)
			#expect(abs(actual.redComponent - expected.redComponent) < 0.001)
			#expect(abs(actual.greenComponent - expected.greenComponent) < 0.001)
			#expect(abs(actual.blueComponent - expected.blueComponent) < 0.001)
			#expect(abs(actual.alphaComponent - expected.alphaComponent) < 0.001)
			editor.setSelectedRange(NSRange(
				location: 0,
				length: 3
			))
			NotificationCenter.default.post(
				name: ColorPreferences.didChange,
				object: nil
			)
			#expect(editor.selectedRange() == NSRange(
				location: 0,
				length: 3
			))
			editor.string = sample.1
			let character = keyCode == 53 ? "\u{1b}" : keyCode == 76 ? "\u{3}" : "\r"
			let event = try #require(NSEvent.keyEvent(
				with: .keyDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: sheet.windowNumber,
				context: nil,
				characters: character,
				charactersIgnoringModifiers: character,
				isARepeat: false,
				keyCode: keyCode
			))
			sheet.sendEvent(event)
			var iterator = result.stream.makeAsyncIterator()
			let response = try #require(await iterator.next())
			#expect(response == (keyCode == 53 ? nil : [sample.1]))
			#expect(await iterator.next() == nil)
			for button in buttons
			{
				_ = button.dispatchConfiguredAction()
			}
			var repeated = false
			prompt.beginSheet(in: parent)
			{
				_ in repeated = true
			}
			#expect(!repeated)
			#expect(parent.attachedSheet == nil)
		}
	}

	private func expectFont(
		_ value: NSFont?,
		size: CGFloat,
		weight: Int
	) throws
	{
		let font = try #require(value)
		#expect(font.pointSize == size)
		let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
		let axes = try #require(CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]])
		let weightAxis = try #require(axes.first
		{
			($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == 0x77676874
		})
		let resolved = variations?[NSNumber(value: 0x77676874)]
			?? (weightAxis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)
		#expect(resolved?.intValue == weight)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
