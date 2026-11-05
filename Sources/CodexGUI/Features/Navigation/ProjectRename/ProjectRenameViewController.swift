import AppKit

@MainActor
final class ProjectRenameViewController: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	var onRemove: (() -> Void)?
	let pathLabel = NSTextField(labelWithString: "")
	let removeButton = DesktopStyledButton(
		title: "Remove local project",
		presentation: .link,
		size: .regular
	)
	let input = ProjectRenameInputView(frame: .zero)
	let cancelButton = DesktopStyledButton(
		title: "Cancel",
		presentation: .dialogCancel,
		size: .regular
	)
	let saveButton = DesktopStyledButton(
		title: "Save",
		presentation: .dialogPrimary,
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
		title: "Edit project",
		message: "Keep it short and recognizable",
		content: makeContent(),
		actions: [cancelButton, saveButton],
		leadingAction: removeButton,
		style: .projectEdit
	)

	private func makeContent() -> NSView
	{
		pathLabel.setTypographyRole(TypographyTokens.Connections.body)
		pathLabel.textColor = AppKitColorTokens.secondaryText
		pathLabel.lineBreakMode = .byTruncatingMiddle
		let stack = AppKitLayout.verticalStack(
			[input, pathLabel],
			spacing: 14
		)
		input.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	override func loadView()
	{
		for button in [cancelButton, saveButton]
		{
			button.target = self
		}
		removeButton.target = self
		removeButton.action = #selector(remove)
		saveButton.action = #selector(save)
		saveButton.keyEquivalent = "\r"
		cancelButton.action = #selector(cancel)
		dialog.onClose =
		{
			[weak self] in self?.onDecision?(false)
		}
		closeButton.setAccessibilityLabel("Close project edit")
		input.field.nextKeyView = removeButton
		removeButton.nextKeyView = cancelButton
		cancelButton.nextKeyView = saveButton
		saveButton.nextKeyView = closeButton
		closeButton.nextKeyView = input.field
		view = dialog
	}

	@objc private func remove()
	{
		onRemove?()
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
