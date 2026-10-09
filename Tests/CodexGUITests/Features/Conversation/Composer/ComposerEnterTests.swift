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
	@Test(
		arguments: [UInt16(36), UInt16(76)],
		["First", "/sta", "First\nSecond"]
	)
	func shiftReturnKeyInsertsNewlineWithoutSending(
		keyCode: UInt16,
		text: String
	) throws
	{
		let controller = ConversationViewController()
		controller.loadViewIfNeeded()
		let window = NSWindow(
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
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.close()
		}
		#expect(window.makeFirstResponder(controller.composer))
		controller.composer.string = text
		controller.composer.setSelectedRange(NSRange(
			location: (text as NSString).length,
			length: 0
		))
		controller.updateComposerCompletion()
		var sends = 0
		var commands = 0
		var drafts: [String] = []
		controller.onSend =
		{
			sends += 1
		}
		controller.onDraftChange =
		{
			drafts.append($0)
		}
		controller.onSlashCommand =
		{
			_ in commands += 1
		}
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [.shift],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "\r",
			charactersIgnoringModifiers: "\r",
			isARepeat: false,
			keyCode: keyCode
		))

		controller.composer.keyDown(with: event)

		#expect(sends == 0)
		#expect(commands == 0)
		#expect(controller.composer.string == text + "\n")
		#expect(drafts.last == text + "\n")
	}

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
