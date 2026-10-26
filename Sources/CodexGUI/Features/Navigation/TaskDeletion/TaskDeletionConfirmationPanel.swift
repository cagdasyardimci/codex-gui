import AppKit

@MainActor
final class TaskDeletionConfirmationPanel: DesktopConfirmationPanel
{
	override var returnKeyDecision: Bool?
	{
		false
	}
}
