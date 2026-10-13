import AppKit

@MainActor
final class ProjectRenameViewController: NSViewController
{
	var onDecision: ((Bool) -> Void)?
	let headingLabel = NSTextField(labelWithString: "Rename project")
	let subtitleLabel = NSTextField(labelWithString: "Keep it short and recognizable")
	let input = ProjectRenameInputView(frame: .zero)
	let closeButton = NSButton(
		title: "Close",
		target: nil,
		action: nil
	)
	let cancelButton = ProjectRenameButton(
		title: "Cancel",
		target: nil,
		action: nil
	)
	let saveButton = ProjectRenameButton(
		title: "Save",
		target: nil,
		action: nil
	)

	override func loadView()
	{
		let surface = DesktopSurface(
			AppKitColorTokens.elevated,
			cornerRadius: 20
		)
		surface.setAccessibilityLabel("Rename project")
		headingLabel.font = .systemFont(
			ofSize: 20,
			weight: .semibold
		)
		headingLabel.textColor = .labelColor
		subtitleLabel.font = .systemFont(ofSize: 14)
		subtitleLabel.textColor = AppKitColorTokens.terminalMutedText
		input.field.setAccessibilityLabel("Project name")
		AppKitControlStyling.styleButton(
			closeButton,
			icon: .xCrossed
		)
		closeButton.imagePosition = .imageOnly
		closeButton.target = self
		closeButton.action = #selector(cancel)
		closeButton.setAccessibilityLabel("Close project rename")
		closeButton.keyEquivalent = "\u{1b}"
		for button in [cancelButton, saveButton]
		{
			button.isBordered = false
			button.bezelStyle = .inline
			button.font = .systemFont(ofSize: 14)
			button.target = self
		}
		saveButton.isPrimary = true
		saveButton.action = #selector(save)
		saveButton.keyEquivalent = "\r"
		cancelButton.action = #selector(cancel)
		input.field.nextKeyView = cancelButton
		cancelButton.nextKeyView = saveButton
		saveButton.nextKeyView = closeButton
		closeButton.nextKeyView = input.field
		for child in [headingLabel, subtitleLabel, input, closeButton, cancelButton, saveButton]
		{
			child.translatesAutoresizingMaskIntoConstraints = false
			surface.addSubview(child)
		}
		NSLayoutConstraint.activate([
			surface.widthAnchor.constraint(equalToConstant: 420),
			surface.heightAnchor.constraint(equalToConstant: 186),
			headingLabel.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: 20
			),
			headingLabel.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: 22
			),
			headingLabel.heightAnchor.constraint(equalToConstant: 24),
			headingLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: closeButton.leadingAnchor,
				constant: -12
			),
			closeButton.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -22
			),
			closeButton.centerYAnchor.constraint(equalTo: headingLabel.centerYAnchor),
			closeButton.widthAnchor.constraint(equalToConstant: 16),
			closeButton.heightAnchor.constraint(equalToConstant: 16),
			subtitleLabel.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
			subtitleLabel.topAnchor.constraint(
				equalTo: headingLabel.bottomAnchor,
				constant: 8
			),
			input.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
			input.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -20
			),
			input.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: 85
			),
			input.heightAnchor.constraint(equalToConstant: 36),
			saveButton.trailingAnchor.constraint(equalTo: input.trailingAnchor),
			saveButton.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -20
			),
			saveButton.widthAnchor.constraint(equalToConstant: 66),
			saveButton.heightAnchor.constraint(equalToConstant: 32),
			cancelButton.trailingAnchor.constraint(
				equalTo: saveButton.leadingAnchor,
				constant: -12
			),
			cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
			cancelButton.widthAnchor.constraint(equalToConstant: 78),
			cancelButton.heightAnchor.constraint(equalToConstant: 32),
		])
		view = surface
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
