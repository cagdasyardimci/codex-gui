import AppKit

@MainActor
final class ProjectRenamePanel: DesktopConfirmationPanel
{
	var onSave: (() -> Void)?
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
		guard !hasCompletedDecision, sheetParent != nil
		else
		{
			return
		}
		if save, !makeFirstResponder(nil)
		{
			return
		}
		finishDecision(save)
	}
}
