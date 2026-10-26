import AppKit

@MainActor
final class TaskDeletionConfirmationView: DesktopConfirmationDialogView
{
	var deleteButton: DesktopActionButton
	{
		confirmButton
	}

	init()
	{
		super.init(
			title: "Delete task?",
			message: "This permanently deletes the task and its subagent tasks.\n"
				+ "This cannot be undone.",
			confirmTitle: "Delete",
			intent: .destructive
		)
		dialog.setAccessibilityLabel("Task deletion confirmation")
		cancelButton.setAccessibilityLabel("Cancel task deletion")
		deleteButton.setAccessibilityLabel("Confirm task deletion")
		closeButton.setAccessibilityLabel("Close task deletion confirmation")
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
