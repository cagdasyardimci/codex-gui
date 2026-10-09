import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Composer Return behavior",
	.serialized
)
struct ComposerEnterTests
{
	@Test func returnSendsSingleLineDraftWithoutChangingText()
	{
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		controller.composer.string = "Send this draft"
		var sends = 0
		controller.onSend =
		{
			sends += 1
		}

		controller.composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))

		#expect(sends == 1)
		#expect(controller.composer.string == "Send this draft")
	}

	@Test(arguments: ["First\nSecond", "First\n", "First\rSecond", "First\u{2028}Second"])
	func returnInsertsNewlineInMultilineDraft(text: String)
	{
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		controller.composer.string = text
		controller.composer.setSelectedRange(NSRange(
			location: (text as NSString).length,
			length: 0
		))
		var sends = 0
		controller.onSend =
		{
			sends += 1
		}

		controller.composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))

		#expect(sends == 0)
		#expect(controller.composer.string == text + "\n")
	}

	@Test func shiftReturnStartsMultilineDraftAndCommandReturnShortcutRemainsConfigured()
	{
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		controller.composer.string = "First"
		controller.composer.setSelectedRange(NSRange(
			location: 5,
			length: 0
		))
		var sends = 0
		controller.onSend =
		{
			sends += 1
		}

		controller.composer.doCommand(by: #selector(NSResponder.insertLineBreak(_:)))

		#expect(sends == 0)
		#expect(controller.composer.string == "First\u{2028}")
		#expect(controller.sendButton.keyEquivalent == "\r")
		#expect(controller.sendButton.keyEquivalentModifierMask == [.command])
	}
}
