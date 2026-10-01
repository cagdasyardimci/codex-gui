import AppKit

@MainActor
final class ProjectTextEditor: NSViewController
{
	enum Kind
	{
		case context(ProjectContextItem?)
		case prompt(SavedPrompt?)
	}

	enum Result
	{
		case context(ProjectContextItem)
		case prompt(SavedPrompt)
	}

	private let kind: Kind
	private let titleField = NSTextField()
	private let pathField = NSTextField()
	private let bodyView = NSTextView()
	private let kindButton = NSPopUpButton()
	private let includeButton = NSButton(
		checkboxWithTitle: "Include in requests",
		target: nil,
		action: nil
	)
	private var onSave: ((Result) -> Void)?
	private var onDelete: (() -> Void)?

	init(kind: Kind)
	{
		self.kind = kind
		super.init(
			nibName: nil,
			bundle: nil
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func loadView()
	{
		let container = DesktopSurface(DesktopTheme.canvas)
		let heading = populateFields()
		titleField.placeholderString = "Title"
		titleField.setAccessibilityLabel("Title")

		let pathRow = makeReferencePathRow()
		configureContextOptions()
		let bodyScroll = makeBodyScrollView()

		let buttons = makeEditorActionsRow()

		var controls: [NSView] = [DesktopTheme.sectionLabel(heading), titleField]
		if case .context = kind
		{
			controls += [kindButton, pathRow, includeButton]
		}
		controls += [bodyScroll, buttons]
		let stack = AppKitLayout.verticalStack(controls)
		AppKitLayout.pin(
			stack,
			to: container
		)
		titleField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		bodyScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		if case .context = kind
		{
			pathRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		view = container
	}

	private func populateFields() -> String
	{
		let heading: String
		switch kind
		{
		case .context(let item):
			heading = item == nil ? "New Context Item" : "Edit Context Item"
			titleField.stringValue = item?.title ?? ""
			pathField.stringValue = item?.referencePath ?? ""
			bodyView.string = item?.body ?? ""
			includeButton.state = item?.isIncluded == true ? .on : .off
		case .prompt(let prompt):
			heading = prompt == nil ? "New Saved Prompt" : "Edit Saved Prompt"
			titleField.stringValue = prompt?.title ?? ""
			bodyView.string = prompt?.instructions ?? ""
		}
		return heading
	}

	private func makeReferencePathRow() -> NSStackView
	{
		pathField.placeholderString = "Project-relative or absolute file path"
		pathField.setAccessibilityLabel("Reference file path")
		let chooseFileButton = NSButton(
			title: "Choose File…",
			target: self,
			action: #selector(chooseFile)
		)
		chooseFileButton.setAccessibilityLabel("Choose a reference file")
		DesktopTheme.styleButton(
			chooseFileButton,
			icon: .folder
		)
		pathField.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		return AppKitLayout.horizontalStack([pathField, chooseFileButton])
	}

	private func configureContextOptions()
	{
		for itemKind in ProjectContextItemKind.allCases
		{
			kindButton.addItem(withTitle: itemKind.displayTitle)
			kindButton.lastItem?.representedObject = itemKind.rawValue
		}
		if case .context(let item) = kind
		{
			kindButton.selectItem(
				withTitle: item?.kind.displayTitle ?? ProjectContextItemKind.note.displayTitle
			)
		}
		kindButton.setAccessibilityLabel("Context item type")
		DesktopTheme.stylePopup(kindButton)
		includeButton.setAccessibilityLabel("Include this context item in requests")
	}

	private func makeBodyScrollView() -> NSScrollView
	{
		bodyView.isRichText = false
		bodyView.font = .systemFont(ofSize: 13)
		bodyView.textContainerInset = NSSize(
			width: 10,
			height: 10
		)
		bodyView.setAccessibilityLabel("Context details or prompt instructions")
		let bodyScroll = NSScrollView()
		bodyScroll.documentView = bodyView
		bodyScroll.hasVerticalScroller = true
		bodyScroll.autohidesScrollers = true
		bodyScroll.borderType = .bezelBorder
		bodyScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
		return bodyScroll
	}

	private func makeEditorActionsRow() -> NSStackView
	{
		let saveButton = NSButton(
			title: "Save",
			target: self,
			action: #selector(save)
		)
		saveButton.setAccessibilityLabel("Save project context")
		DesktopTheme.styleButton(
			saveButton,
			prominent: true
		)
		let cancelButton = NSButton(
			title: "Cancel",
			target: self,
			action: #selector(cancel)
		)
		cancelButton.setAccessibilityLabel("Cancel editing")
		DesktopTheme.styleButton(cancelButton)
		let deleteButton = NSButton(
			title: "Delete",
			target: self,
			action: #selector(deleteEntry)
		)
		deleteButton.setAccessibilityLabel("Delete project context entry")
		DesktopTheme.styleButton(deleteButton)
		switch kind
		{
		case .context(let item): deleteButton.isHidden = item == nil
		case .prompt(let prompt): deleteButton.isHidden = prompt == nil
		}
		return AppKitLayout.horizontalStack([deleteButton, cancelButton, saveButton])
	}

	func present(
		in window: NSWindow,
		onSave: @escaping (Result) -> Void,
		onDelete: @escaping () -> Void
	)
	{
		self.onSave = onSave
		self.onDelete = onDelete
		let sheet = NSWindow(contentViewController: self)
		sheet.title = "Project Context"
		sheet.setContentSize(NSSize(
			width: min(
				520,
				max(
					360,
					window.frame.width - 80
				)
			),
			height: 390
		))
		window.beginSheet(sheet)
		sheet.makeFirstResponder(titleField)
	}

	@objc private func save()
	{
		let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !title.isEmpty
		else
		{
			view.window?.makeFirstResponder(titleField)
			return
		}
		let result: Result
		switch kind
		{
		case .context(let old):
			let selectedKind =
				ProjectContextItemKind(
					rawValue:
					kindButton.selectedItem?.representedObject as? String ?? ""
				) ?? .note
			let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			result = .context(
				ProjectContextItem(
					id: old?.id ?? UUID().uuidString,
					kind: selectedKind,
					title: title,
					body: bodyView.string,
					referencePath: path.isEmpty ? nil : path,
					isIncluded: includeButton.state == .on
				)
			)
		case .prompt(let old):
			result = .prompt(
				SavedPrompt(
					id: old?.id ?? UUID().uuidString,
					title: title,
					instructions: bodyView.string
				)
			)
		}
		close()
		onSave?(result)
	}

	@objc private func cancel()
	{
		close()
	}

	@objc private func deleteEntry()
	{
		close()
		onDelete?()
	}

	@objc private func chooseFile()
	{
		guard let window = view.window
		else
		{
			return
		}
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.allowsMultipleSelection = false
		panel.prompt = "Use Reference"
		panel.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .OK, let url = panel.url
			else
			{
				return
			}
			self?.pathField.stringValue = url.path
			self?.kindButton
				.selectItem(withTitle: ProjectContextItemKind.referenceFile.displayTitle)
		}
	}

	private func close()
	{
		guard let sheet = view.window, let parent = sheet.sheetParent
		else
		{
			return
		}
		parent.endSheet(sheet)
	}
}
