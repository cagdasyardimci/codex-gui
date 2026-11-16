import AppKit
import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ContextComposerTextViewTests
{
	@Test func absentSkillSynchronizationPreservesNativeSelections()
	{
		let composer = ContextComposerTextView()
		composer.string = "Keep this draft"
		let selections = [
			NSValue(range: NSRange(
				location: 0,
				length: 4
			)),
			NSValue(range: NSRange(
				location: 10,
				length: 5
			)),
		]
		composer.selectedRanges = selections
		#expect(!composer.renderSkill(
			nil,
			title: nil
		))
		#expect(composer.selectedRanges == selections)
		#expect(composer.string == "Keep this draft")
	}

	@Test func nontextImageClipboardEnablesNativePasteAndPreservesEditableText() throws
	{
		_ = NSApplication.shared
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		let bitmap = try #require(
			NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 2,
				pixelsHigh: 2,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			)
		)
		bitmap.setColor(
			.systemBlue,
			atX: 0,
			y: 0
		)
		let png = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		#expect(pasteboard.setData(
			png,
			forType: .png
		))
		#expect(pasteboard.string(forType: .string) == nil)
		let composer = ContextComposerTextView()
		composer.isEditable = true
		composer.isRichText = false
		composer.string = "Existing draft"
		composer.imagePasteboard = pasteboard
		var attachment: (NSImage, String)?
		composer.onImage =
		{
			image, title in attachment = (image, title)
		}
		let paste = NSMenuItem(
			title: "Paste",
			action: #selector(NSText.paste(_:)),
			keyEquivalent: "v"
		)

		#expect(composer.validateMenuItem(paste))
		#expect(composer.validateUserInterfaceItem(paste))
		composer.paste(nil)
		#expect(attachment?.0.size == NSSize(
			width: 2,
			height: 2
		))
		#expect(attachment?.1 == "Pasted image")
		#expect(composer.string == "Existing draft")
		composer.isEditable = false
		#expect(!composer.validateMenuItem(paste))
		#expect(!composer.validateUserInterfaceItem(paste))
	}
}
