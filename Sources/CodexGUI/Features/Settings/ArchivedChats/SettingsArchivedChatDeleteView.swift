import AppKit

@MainActor
final class SettingsArchivedChatDeleteView: DesktopConfirmationDialogView
{
	var deleteButton: DesktopActionButton
	{
		confirmButton
	}

	init()
	{
		super.init(
			title: "Delete archived chat?",
			message: "This permanently deletes the archived chat",
			confirmTitle: "Delete",
			intent: .destructive
		)
		dialog.setAccessibilityLabel("Delete archived chat confirmation")
		cancelButton.setAccessibilityLabel("Cancel archived chat deletion")
		deleteButton.setAccessibilityLabel("Delete archived chat")
		closeButton.setAccessibilityLabel("Close archived chat deletion confirmation")
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}

@MainActor
final class SettingsArchivedChatDeletePanel: DesktopConfirmationPanel
{
	override var returnKeyDecision: Bool?
	{
		false
	}
}
