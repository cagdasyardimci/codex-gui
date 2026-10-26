import AppKit

@MainActor
final class SavedPromptsSectionViewController: NSViewController
{
	var onSelectPrompt: ((String) -> Void)?
	var makeSaveReceiver: (() -> (SavedPrompt) -> Void)?
	var makeDeleteReceiver: (() -> (String) -> Void)?
	var makeProjectSelectionReceiver: ((@escaping () -> Void) -> () -> Void)?
	var makeInsertionReceiver: ((String) -> () -> Void)?

	private let stack = NSStackView()
	private var prompts: [SavedPrompt] = []
	private var selectedPromptID: String?

	func render(
		prompts: [SavedPrompt],
		selectedPromptID: String?
	)
	{
		self.prompts = prompts
		self.selectedPromptID = selectedPromptID
		if isViewLoaded
		{
			rebuild()
		}
	}

	override func loadView()
	{
		let surface = NSView()
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 0
		)
		view = surface
		rebuild()
	}

	func rebuild()
	{
		for subview in stack.arrangedSubviews
		{
			stack.removeArrangedSubview(subview)
			subview.removeFromSuperview()
		}

		add(AppKitControlStyling.sectionLabel("Saved Prompts"))
		let detail = NSTextField(
			wrappingLabelWithString:
			"Inspect instructions, then insert them into the editable draft."
		)
		detail.textColor = .secondaryLabelColor
		detail.font = .systemFont(ofSize: 11)
		add(detail)
		for prompt in prompts
		{
			addPromptRow(
				prompt,
				selectedID: selectedPromptID
			)
		}
		let button = DesktopStyledButton(
			title: "Add Prompt…",
			target: self,
			action: #selector(addPrompt)
		)
		button.setAccessibilityLabel("Add Prompt…")
		button.symbol = .plus
		add(button)
	}

	private func add(_ control: NSView)
	{
		if let button = control as? NSButton, !(button is DesktopStyledButton)
		{
			button.controlSize = .small
			button.font = .systemFont(ofSize: 12)
			AppKitLayout.compressHorizontally(button)
			button.toolTip = button.toolTip ?? button.title
		}
		stack.addArrangedSubview(control)
		control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	private func addPromptRow(
		_ prompt: SavedPrompt,
		selectedID: String?
	)
	{
		let button = DesktopStyledButton(
			title: "\(prompt.id == selectedID ? "✓ " : "")\(prompt.title)…",
			target: self,
			action: #selector(inspectPrompt(_:))
		)
		button.identifier = NSUserInterfaceItemIdentifier(prompt.id)
		button.toolTip = prompt.instructions
		button.setAccessibilityLabel("Inspect saved prompt \(prompt.title)")
		button.symbol = .quote
		add(button)
	}

	@objc private func addPrompt()
	{
		editPrompt(nil)
	}

	private func editPrompt(_ existing: SavedPrompt?)
	{
		guard let window = view.window
		else
		{
			return
		}
		let editor = ProjectTextEditor(kind: .prompt(existing))
		let savePrompt = makeSaveReceiver?() ??
		{
			(_: SavedPrompt) in
		}
		let deletePrompt = makeDeleteReceiver?() ??
		{
			(_: String) in
		}
		editor.present(in: window)
		{
			result in
			guard case .prompt(let prompt) = result
			else
			{
				return
			}
			savePrompt(prompt)
		} onDelete:
		{
			if let existing
			{
				deletePrompt(existing.id)
			}
		}
	}

	@objc private func inspectPrompt(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				let prompt = prompts.first(where:
				{
					$0.id == id
				}),
				let window = view.window
		else
		{
			return
		}
		let alert = makePromptReviewAlert(
			prompt,
			in: window
		)
		onSelectPrompt?(id)
		let insertPrompt = makeProjectSelectionReceiver?(
			makeInsertionReceiver?(id) ??
			{
			}
		) ??
		{
		}
		let editPrompt = makeProjectSelectionReceiver?(
			{
				[weak self] in
				self?.editPrompt(prompt)
			}
		) ??
		{
		}
		alert.beginSheetModal(for: window)
		{
			response in
			if response == .alertFirstButtonReturn
			{
				insertPrompt()
			}
			else if response == .alertSecondButtonReturn
			{
				editPrompt()
			}
		}
	}

	private func makePromptReviewAlert(
		_ prompt: SavedPrompt,
		in window: NSWindow
	) -> NSAlert
	{
		let alert = NSAlert()
		alert.messageText = prompt.title
		alert.informativeText =
			"Review these saved instructions before inserting them into the draft."
		alert.accessoryView = makePromptInstructionsView(
			prompt,
			in: window
		)
		alert.addButton(withTitle: "Insert into Draft")
		alert.addButton(withTitle: "Edit…")
		alert.addButton(withTitle: "Close")
		return alert
	}

	private func makePromptInstructionsView(
		_ prompt: SavedPrompt,
		in window: NSWindow
	) -> NSScrollView
	{
		let instructions = NSTextView()
		instructions.string = prompt.instructions
		instructions.isEditable = false
		instructions.isSelectable = true
		instructions.font = .systemFont(ofSize: 13)
		instructions.setAccessibilityLabel("Saved prompt instructions")
		let scrollView = NSScrollView()
		scrollView.documentView = instructions
		scrollView.hasVerticalScroller = true
		scrollView.frame = NSRect(
			x: 0,
			y: 0,
			width: min(
				440,
				window.frame.width - 80
			),
			height: 220
		)
		return scrollView
	}
}
