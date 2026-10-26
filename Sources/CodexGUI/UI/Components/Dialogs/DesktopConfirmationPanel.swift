import AppKit

/// Owns a sheet's once-only decision; callers retain validation and operation routing.
@MainActor
class DesktopConfirmationPanel: NSPanel
{
	private(set) var hasCompletedDecision = false

	/// A nil decision leaves Return handling to the native responder chain.
	var returnKeyDecision: Bool?
	{
		nil
	}

	override var canBecomeKey: Bool
	{
		true
	}

	func beginSheet(
		in parent: NSWindow,
		completionHandler: @escaping (NSApplication.ModalResponse) -> Void
	)
	{
		let requestedResponder = initialFirstResponder
		parent.beginSheet(
			self,
			completionHandler: completionHandler
		)
		if let requestedResponder
		{
			initialFirstResponder = requestedResponder
			makeFirstResponder(requestedResponder)
		}
		// AppKit and menu tracking can replace the initial responder during presentation.
		DispatchQueue.main.async
		{
			[weak self, weak requestedResponder] in
			guard let self, let requestedResponder, sheetParent === parent, !hasCompletedDecision
			else
			{
				return
			}
			initialFirstResponder = requestedResponder
			makeFirstResponder(requestedResponder)
		}
	}

	override func sendEvent(_ event: NSEvent)
	{
		if sheetParent != nil, let decision = returnKeyDecision,
			event.type == .keyDown,
			event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
			["\r", "\u{3}"].contains(event.charactersIgnoringModifiers ?? "")
		{
			finishDecision(decision)
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
}
