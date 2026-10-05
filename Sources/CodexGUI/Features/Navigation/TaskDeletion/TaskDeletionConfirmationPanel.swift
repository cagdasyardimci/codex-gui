import AppKit

@MainActor
final class TaskDeletionConfirmationPanel: NSPanel
{
	private var hasCompletedDecision = false

	override var canBecomeKey: Bool
	{
		true
	}

	override func sendEvent(_ event: NSEvent)
	{
		if sheetParent != nil, isUnmodifiedReturnKeyEvent(event)
		{
			finishDecision(false)
			return
		}
		super.sendEvent(event)
	}

	func finishDecision(_ confirmed: Bool)
	{
		guard !hasCompletedDecision, let parent = sheetParent
		else
		{
			return
		}
		hasCompletedDecision = true
		parent.endSheet(
			self,
			returnCode: confirmed ? .OK : .cancel
		)
	}

	override func cancelOperation(_ sender: Any?)
	{
		finishDecision(false)
	}

	private func isUnmodifiedReturnKeyEvent(_ event: NSEvent) -> Bool
	{
		guard event.type == .keyDown,
				event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
		else
		{
			return false
		}
		return event.charactersIgnoringModifiers == "\r"
			|| event.charactersIgnoringModifiers == "\u{3}"
	}
}
