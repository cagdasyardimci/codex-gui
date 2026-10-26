import AppKit

/// A complete confirmation component. Callers provide meaning and keep operation ownership.
@MainActor
class DesktopConfirmationDialogView: NSViewController
{
	enum Intent
	{
		case standard, destructive
	}

	var onDecision: ((Bool) -> Void)?
	let cancelButton: DesktopActionButton
	let confirmButton: DesktopActionButton
	let dialog: DesktopDialogShell
	var headingLabel: NSTextField
	{
		dialog.titleLabel
	}
	var warningLabel: NSTextField
	{
		dialog.messageLabel!
	}
	var closeButton: NSButton
	{
		dialog.closeButton
	}

	init(
		title: String,
		message: String,
		confirmTitle: String,
		intent: Intent
	)
	{
		cancelButton = DesktopActionButton(
			title: "Cancel",
			presentation: .secondary,
			size: .regular
		)
		confirmButton = DesktopActionButton(
			title: confirmTitle,
			presentation: intent == .destructive ? .destructive : .primary,
			size: .regular
		)
		confirmButton.hasDestructiveAction = intent == .destructive
		dialog = DesktopDialogShell(
			title: title,
			message: message,
			actions: [cancelButton, confirmButton]
		)
		super.init(
			nibName: nil,
			bundle: nil
		)
		cancelButton.keyEquivalent = "\r"
		cancelButton.nextKeyView = confirmButton
		confirmButton.nextKeyView = closeButton
		closeButton.nextKeyView = cancelButton
		cancelButton.onAction =
		{
			[weak self] in self?.onDecision?(false)
		}
		confirmButton.onAction =
		{
			[weak self] in self?.onDecision?(true)
		}
		dialog.onClose =
		{
			[weak self] in self?.onDecision?(false)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		view = dialog
	}
}
