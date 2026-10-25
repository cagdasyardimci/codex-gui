import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct ComposerReferenceGeometryTests
{

	@Test func baselineCorrectionPreservesLineBoxesAndSelection() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let editor = controller.composer
		editor.string = "First line\nSecond line"
		let selection = NSRange(
			location: 2,
			length: 3
		)
		editor.setSelectedRange(selection)
		let manager = try #require(editor.layoutManager)
		let container = try #require(editor.textContainer)
		manager.ensureLayout(for: container)

		let standard = NSTextView(frame: editor.bounds)
		standard.font = editor.font
		standard.defaultParagraphStyle = editor.defaultParagraphStyle
		standard.textContainerInset = .zero
		standard.textContainer?.lineFragmentPadding = 0
		standard.string = editor.string
		let standardManager = try #require(standard.layoutManager)
		let standardContainer = try #require(standard.textContainer)
		standardManager.ensureLayout(for: standardContainer)
		#expect(abs(standardManager.location(forGlyphAt: 0).y
				- manager.location(forGlyphAt: 0).y - 2) < 0.01)
		#expect(manager.lineFragmentRect(
			forGlyphAt: 0,
			effectiveRange: nil
		).height == 20)
		#expect(manager.usedRect(for: container).height
			== standardManager.usedRect(for: standardContainer).height)
		#expect(editor.selectedRange() == selection)

		editor.setMarkedText(
			"仮",
			selectedRange: NSRange(
				location: 0,
				length: 1
			),
			replacementRange: selection
		)
		#expect(editor.hasMarkedText())
		let markedSelection = editor.selectedRange()
		manager.ensureLayout(for: container)
		#expect(editor.markedRange() == NSRange(
			location: 2,
			length: 1
		))
		#expect(editor.selectedRange() == markedSelection)
		editor.unmarkText()
		#expect(!editor.hasMarkedText())
		#expect(editor.string == "Fi仮 line\nSecond line")
	}
}
