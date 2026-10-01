import AppKit

@MainActor
final class FullAccessConfirmationPanel: NSPanel
{
	override var canBecomeKey: Bool
	{
		true
	}

	override func cancelOperation(_ sender: Any?)
	{
		sheetParent?.endSheet(
			self,
			returnCode: .cancel
		)
	}
}
