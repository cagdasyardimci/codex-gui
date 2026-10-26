import AppKit

@MainActor
final class ProjectRenameViewController: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	let input = ProjectRenameInputView(frame: .zero)
	let cancelButton = DesktopStyledButton(
		title: "Cancel",
		presentation: .secondary,
		size: .regular
	)
	let saveButton = DesktopStyledButton(
		title: "Save",
		presentation: .primary,
		size: .regular
	)
	var headingLabel: NSTextField
	{
		dialog.titleLabel
	}
	var subtitleLabel: NSTextField
	{
		dialog.messageLabel!
	}
	var closeButton: NSButton
	{
		dialog.closeButton
	}
	private lazy var dialog = DesktopDialogShell(
		title: "Rename project",
		message: "Keep it short and recognizable",
		content: input,
		actions: [cancelButton, saveButton]
	)

	override func loadView()
	{
		for button in [cancelButton, saveButton]
		{
			button.target = self
		}
		saveButton.action = #selector(save)
		saveButton.keyEquivalent = "\r"
		cancelButton.action = #selector(cancel)
		dialog.onClose =
		{
			[weak self] in self?.onDecision?(false)
		}
		closeButton.setAccessibilityLabel("Close project rename")
		input.field.nextKeyView = cancelButton
		cancelButton.nextKeyView = saveButton
		saveButton.nextKeyView = closeButton
		closeButton.nextKeyView = input.field
		view = dialog
	}

	@objc private func save()
	{
		onDecision?(true)
	}

	@objc private func cancel()
	{
		onDecision?(false)
	}
}
