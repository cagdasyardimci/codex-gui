import AppKit

@MainActor
final class ProjectRenamePanel: NSPanel
{
	var onSave: (() -> Void)?
	private var hasCompleted = false
	override var canBecomeKey: Bool
	{
		true
	}

	override func sendEvent(_ event: NSEvent)
	{
		guard event.type == .keyDown
		else
		{
			super.sendEvent(event)
			return
		}
		let isReturn = event.charactersIgnoringModifiers == "\r"
			|| event.charactersIgnoringModifiers == "\u{3}"
		let hasModifiers = !event.modifierFlags.intersection([.command, .control, .option, .shift])
			.isEmpty
		let isComposing = (firstResponder as? NSTextView)?.hasMarkedText() == true
		if sheetParent != nil, event.type == .keyDown, isReturn, !hasModifiers, !isComposing
		{
			onSave?()
			return
		}
		super.sendEvent(event)
	}

	func finish(_ save: Bool)
	{
		guard !hasCompleted, let parent = sheetParent
		else
		{
			return
		}
		if save, !makeFirstResponder(nil)
		{
			return
		}
		hasCompleted = true
		parent.endSheet(
			self,
			returnCode: save ? .OK : .cancel
		)
	}
	override func cancelOperation(_ sender: Any?)
	{
		finish(false)
	}
}
