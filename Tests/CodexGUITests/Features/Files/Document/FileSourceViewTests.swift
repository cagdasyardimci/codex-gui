import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct FileSourceViewTests
{
	@Test func unchangedRenderingPreservesNativeTextAttributesAndSelection() throws
	{
		let source = FileSourceView()
		let text = "# Heading\n😀 source"
		source.render(
			text: text,
			path: "sample.txt",
			editable: true
		)
		let storage = try #require(source.textView.textStorage)
		let selection = NSRange(
			location: 2,
			length: 4
		)
		source.textView.setSelectedRange(selection)
		let counter = StorageEditCounter()
		let observation = NotificationCenter.default.addObserver(
			forName: NSTextStorage.didProcessEditingNotification,
			object: storage,
			queue: nil
		)
		{
			_ in MainActor.assumeIsolated
			{
				counter.value += 1
			}
		}
		defer
		{
			NotificationCenter.default.removeObserver(observation)
		}
		source.render(
			text: text,
			path: "sample.txt",
			editable: false
		)
		#expect(counter.value == 0)
		#expect(source.textView.selectedRange() == selection)
		#expect(!source.textView.isEditable)
		source.render(
			text: text,
			path: "sample.md",
			editable: false
		)
		#expect(counter.value > 0)
		#expect(source.textView.selectedRange() == selection)
	}

	@Test func canonicallyEquivalentReplacementRetainsItsExactUTF8Bytes()
	{
		let source = FileSourceView()
		let original = "caf\u{E9}\r\nsecond"
		let replacement = "cafe\u{301}\r\nsecond"
		#expect(original == replacement)
		source.render(
			text: original,
			path: "sample.txt",
			editable: true
		)
		source.render(
			text: replacement,
			path: "sample.txt",
			editable: true
		)
		#expect(source.textView.string.utf8.elementsEqual(replacement.utf8))
		source.reveal(line: 2)
		#expect(source.textView.selectedRange().location == 7)
	}

	@MainActor private final class StorageEditCounter
	{
		var value = 0
	}
}
