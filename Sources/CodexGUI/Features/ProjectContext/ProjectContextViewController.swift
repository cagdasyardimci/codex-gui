import AppKit

@MainActor
final class ProjectContextViewController: NSViewController
{
	var onUpdate: ((ProjectContext) -> Void)?
	var onInsertPrompt: ((String) -> Void)?

	private let contentStack = NSStackView()
	private var sectionStack: NSStackView?
	private var context = ProjectContext()
	private var models: [ModelOption] = []
	private var availableSkills: [ProjectSkillSelection] = []
	private var statusMessage: String?
	private var ownerIdentity: String?
	private var selectionGeneration = 0
	private var draftOwnerIdentity: String?
	private var draftSelectionGeneration = 0

	override func loadView()
	{
		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = false
		contentStack.orientation = .vertical
		contentStack.alignment = .leading
		contentStack.spacing = 18
		let document = NSView()
		AppKitLayout.pin(
			contentStack,
			to: document,
			inset: 0
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = document
		document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
		scrollView.setAccessibilityLabel("Project context, reusable prompts, skills, and bookmarks")
		view = scrollView
		rebuild()
	}

	func render(_ presentation: ProjectContextPresentation)
	{
		render(
			context: presentation.context,
			models: presentation.models,
			skills: presentation.skills,
			statusMessage: presentation.statusMessage,
			ownerIdentity: presentation.ownerIdentity,
			draftOwnerIdentity: presentation.draftOwnerIdentity
		)
	}

	func render(
		context: ProjectContext,
		models: [ModelOption],
		skills: [ProjectSkillSelection],
		statusMessage: String?,
		ownerIdentity: String? = nil,
		draftOwnerIdentity: String? = nil
	)
	{
		if ownerIdentity != self.ownerIdentity
		{
			selectionGeneration += 1
		}
		if draftOwnerIdentity != self.draftOwnerIdentity
		{
			draftSelectionGeneration += 1
		}
		self.draftOwnerIdentity = draftOwnerIdentity
		guard
			context != self.context || models != self.models || skills != availableSkills
			|| statusMessage != self.statusMessage || ownerIdentity != self.ownerIdentity
		else
		{
			return
		}
		self.ownerIdentity = ownerIdentity
		self.context = context
		self.models = models
		availableSkills = skills
		self.statusMessage = statusMessage
		if isViewLoaded
		{
			rebuild()
		}
	}

	func makePromptInsertionReceiver(id: String) -> () -> Void
	{
		let generation = draftSelectionGeneration
		let receiver: () -> Void =
		{
			[weak self] in
			guard let self, self.draftSelectionGeneration == generation
			else
			{
				return
			}
			self.onInsertPrompt?(id)
		}

		return receiver
	}

	/// A modal editor can deliver its result only while its original project is visible.
	func makeContextMutationReceiver<Value>(
		_ mutation: @escaping (
			inout ProjectContext,
			Value
		) -> Void
	) -> (Value) -> Void
	{
		let generation = selectionGeneration
		let receiver: (Value) -> Void =
		{
			[weak self] value in
			guard let self, self.selectionGeneration == generation
			else
			{
				return
			}
			mutation(
				&self.context,
				value
			)
			self.onUpdate?(self.context)
			self.rebuild()
		}

		return receiver
	}

	private func rebuild()
	{
		sectionStack = nil
		for subview in contentStack.arrangedSubviews
		{
			contentStack.removeArrangedSubview(subview)
			subview.removeFromSuperview()
		}

		addContextSection()
		addSavedPromptsSection()
		addSkillSection()
		addModelPreferencesSection()
		addBookmarksSection()
	}

	private func addContextSection()
	{
		addHeader(
			"Project Context",
			detail: "Select each item you want included in new requests."
		)
		if let statusMessage
		{
			addDetail(statusMessage)
		}
		for item in context.items
		{
			addContextRow(item)
		}
		addButton(
			"Add Context Item…",
			action: #selector(addContextItem)
		)
	}

	private func addSavedPromptsSection()
	{
		addHeader(
			"Saved Prompts",
			detail: "Inspect instructions, then insert them into the editable draft."
		)
		for prompt in context.savedPrompts
		{
			addPromptRow(prompt)
		}
		addButton(
			"Add Prompt…",
			action: #selector(addPrompt)
		)
	}

	private func addSkillSection()
	{
		addHeader(
			"Skill",
			detail: "The selected skill and invocation text are shown before sending."
		)
		add(makeSkillSelectionButton())
		if let skill = context.selectedSkill
		{
			addDetail("\(skill.invocationText) — \(skill.description)")
		}
	}

	private func makeSkillSelectionButton() -> NSPopUpButton
	{
		let skillButton = NSPopUpButton()
		skillButton.addItem(withTitle: "No skill")
		skillButton.item(at: 0)?.representedObject = ""
		for skill in availableSkills
		{
			skillButton.addItem(withTitle: skill.name)
			skillButton.lastItem?.representedObject = skill.path ?? skill.name
			skillButton.lastItem?.toolTip = "\(skill.description)\n\(skill.path ?? "")"
		}
		if let selected = context.selectedSkill,
			!availableSkills.contains(where:
			{
				$0.name == selected.name
					&& ($0.path == selected.path || selected.path == nil)
			})
		{
			skillButton.addItem(withTitle: "Unavailable: \(selected.name)")
			skillButton.lastItem?.representedObject = selected.name
		}
		let selectedIndex = context.selectedSkill.flatMap
		{
			selected in
			availableSkills.firstIndex
			{
				$0.name == selected.name && ($0.path == selected.path || selected.path == nil)
			}.map
			{
				$0 + 1
			}
		}
		skillButton.selectItem(
			at: selectedIndex
				?? (context.selectedSkill == nil
					? 0
					: skillButton.numberOfItems - 1)
		)
		skillButton.target = self
		skillButton.action = #selector(selectSkill(_:))
		skillButton.setAccessibilityLabel("Selected project skill")
		return skillButton
	}

	private func addModelPreferencesSection()
	{
		addHeader(
			"Project Model",
			detail: "Use project choices or follow global preferences."
		)
		let preferenceToggle = NSButton(
			checkboxWithTitle: "Use project model and effort",
			target: self,
			action: #selector(toggleProjectPreferences(_:))
		)
		preferenceToggle.state = context.modelPreference == nil ? .off : .on
		preferenceToggle.setAccessibilityLabel("Use project model and reasoning effort preferences")
		add(preferenceToggle)

		add(makeModelPreferenceButton())
		add(makeEffortPreferenceButton())
	}

	private func makeModelPreferenceButton() -> NSPopUpButton
	{
		let modelButton = NSPopUpButton()
		modelButton.addItem(withTitle: "Backend default")
		modelButton.item(at: 0)?.representedObject = ""
		for model in models
		{
			modelButton.addItem(withTitle: model.displayName)
			modelButton.lastItem?.representedObject = model.id
		}
		if let id = context.modelPreference?.modelID, !models.contains(where:
			{
				$0.id == id
			})
		{
			modelButton.addItem(withTitle: "Unavailable: \(id)")
			modelButton.lastItem?.representedObject = id
		}
		modelButton.selectItem(
			at: modelButton.itemArray.firstIndex
			{
				($0.representedObject as? String)
					== (context.modelPreference?.modelID ?? "")
			} ?? 0
		)
		modelButton.target = self
		modelButton.action = #selector(selectModel(_:))
		modelButton.setAccessibilityLabel("Project model preference")
		modelButton.isEnabled = context.modelPreference != nil
		return modelButton
	}

	private func makeEffortPreferenceButton() -> NSPopUpButton
	{
		let effortButton = NSPopUpButton()
		effortButton.addItem(withTitle: "Backend default")
		effortButton.item(at: 0)?.representedObject = ""
		let model =
			models.first
				{
					$0.id == context.modelPreference?.modelID
				}
				?? models.first(where: \.isDefault)
		let efforts = model?.supportedReasoningEfforts ?? []
		for effort in efforts
		{
			effortButton.addItem(withTitle: effort.capitalized)
			effortButton.lastItem?.representedObject = effort
		}
		if let effort = context.modelPreference?.effort, !efforts.contains(effort)
		{
			effortButton.addItem(withTitle: "Unavailable: \(effort)")
			effortButton.lastItem?.representedObject = effort
		}
		effortButton.selectItem(
			at: effortButton.itemArray.firstIndex
			{
				($0.representedObject as? String)
					== (context.modelPreference?.effort ?? "")
			} ?? 0
		)
		effortButton.target = self
		effortButton.action = #selector(selectEffort(_:))
		effortButton.setAccessibilityLabel("Project reasoning effort preference")
		effortButton.isEnabled = context.modelPreference != nil
		return effortButton
	}

	private func addBookmarksSection()
	{
		addHeader(
			"Bookmarks",
			detail: "Open a saved request, answer, decision, file, or failure."
		)
		for bookmark in context.bookmarks
		{
			addBookmarkRow(bookmark)
		}
		if context.bookmarks.isEmpty
		{
			addDetail("No bookmarks saved yet.")
		}
	}

	private func addHeader(
		_ title: String,
		detail: String
	)
	{
		let surface = NSView()
		let stack = AppKitLayout.verticalStack(
			[],
			spacing: 8
		)
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 0
		)
		contentStack.addArrangedSubview(surface)
		surface.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
		sectionStack = stack
		add(DesktopTheme.sectionLabel(title))
		addDetail(detail)
	}

	private func addDetail(_ text: String)
	{
		let label = NSTextField(wrappingLabelWithString: text)
		label.textColor = .secondaryLabelColor
		label.font = .systemFont(ofSize: 11)
		add(label)
	}

	private func add(_ control: NSView)
	{
		if let popup = control as? NSPopUpButton
		{
			DesktopTheme.stylePopup(popup)
		}
		else if let button = control as? NSButton
		{
			button.controlSize = .small
			button.font = .systemFont(ofSize: 12)
			AppKitLayout.compressHorizontally(button)
			button.toolTip = button.toolTip ?? button.title
		}
		let stack = sectionStack ?? contentStack
		stack.addArrangedSubview(control)
		control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
	}

	private func addButton(
		_ title: String,
		action: Selector
	)
	{
		let button = NSButton(
			title: title,
			target: self,
			action: action
		)
		button.setAccessibilityLabel(title)
		DesktopTheme.styleButton(
			button,
			symbol: "plus"
		)
		add(button)
	}

	private func addContextRow(_ item: ProjectContextItem)
	{
		let inclusionButton = NSButton(
			checkboxWithTitle: "\(item.kind.displayTitle): \(item.title)",
			target: self,
			action: #selector(toggleContextItem(_:))
		)
		inclusionButton.state = item.isIncluded ? .on : .off
		inclusionButton.identifier = NSUserInterfaceItemIdentifier(item.id)
		inclusionButton.toolTip = item.referencePath ?? item.body
		inclusionButton.setAccessibilityLabel("Include \(item.title) in requests")
		inclusionButton.controlSize = .small
		inclusionButton.font = .systemFont(ofSize: 12)
		AppKitLayout.compressHorizontally(inclusionButton)

		let editButton = NSButton(
			title: "Edit…",
			target: self,
			action: #selector(editContextItem(_:))
		)
		editButton.identifier = NSUserInterfaceItemIdentifier(item.id)
		editButton.setAccessibilityLabel("Edit \(item.title)")
		DesktopTheme.styleButton(editButton)
		editButton.controlSize = .small
		editButton.font = .systemFont(ofSize: 11)

		add(AppKitLayout.horizontalStack(
			[inclusionButton, editButton],
			spacing: 4
		))
	}

	private func addPromptRow(_ prompt: SavedPrompt)
	{
		let selected = prompt.id == context.selectedPromptID
		let button = NSButton(
			title: "\(selected ? "✓ " : "")\(prompt.title)…",
			target: self,
			action: #selector(inspectPrompt(_:))
		)
		button.identifier = NSUserInterfaceItemIdentifier(prompt.id)
		button.toolTip = prompt.instructions
		button.setAccessibilityLabel("Inspect saved prompt \(prompt.title)")
		DesktopTheme.styleButton(
			button,
			symbol: "text.quote"
		)
		add(button)
	}

	private func addBookmarkRow(_ bookmark: ConversationBookmark)
	{
		let button = NSButton(
			title: "\(bookmark.kind.displayTitle): \(bookmark.label)",
			target: self,
			action: #selector(openBookmark(_:))
		)
		button.identifier = NSUserInterfaceItemIdentifier(bookmark.id)
		button
			.setAccessibilityLabel(
				"Open bookmarked \(bookmark.kind.displayTitle): \(bookmark.label)"
			)
		DesktopTheme.styleButton(
			button,
			symbol: "bookmark"
		)
		add(button)
	}

	@objc private func addContextItem()
	{
		editContextItem(nil)
	}

	@objc private func editContextItem(_ sender: NSButton?)
	{
		let id = sender?.identifier?.rawValue
		let existing = context.items.first
		{
			$0.id == id
		}
		guard let window = view.window
		else
		{
			return
		}
		let editor = ProjectTextEditor(kind: .context(existing))
		let saveItem = makeContextMutationReceiver
		{
			(context: inout ProjectContext, item: ProjectContextItem) in
			if let index = context.items.firstIndex(where:
				{
					$0.id == item.id
				})
			{
				context.items[index] = item
			}
			else
			{
				context.items.append(item)
			}
		}
		let deleteItem = makeContextMutationReceiver
		{
			(context: inout ProjectContext, id: String) in
			context.items.removeAll
			{
				$0.id == id
			}
		}
		editor.present(in: window)
		{
			result in
			guard case .context(let item) = result
			else
			{
				return
			}
			saveItem(item)
		} onDelete:
		{
			if let id
			{
				deleteItem(id)
			}
		}
	}

	@objc private func toggleContextItem(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				let index = context.items.firstIndex(where:
				{
					$0.id == id
				})
		else
		{
			return
		}
		context.items[index].isIncluded = sender.state == .on
		onUpdate?(context)
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
		let savePrompt = makeContextMutationReceiver
		{
			(context: inout ProjectContext, prompt: SavedPrompt) in
			if let index = context.savedPrompts.firstIndex(where:
				{
					$0.id == prompt.id
				})
			{
				context.savedPrompts[index] = prompt
			}
			else
			{
				context.savedPrompts.append(prompt)
			}
		}
		let deletePrompt = makeContextMutationReceiver
		{
			(context: inout ProjectContext, id: String) in
			context.savedPrompts.removeAll
			{
				$0.id == id
			}
			if context.selectedPromptID == id
			{
				context.selectedPromptID = nil
			}
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
				let prompt = context.savedPrompts.first(where:
				{
					$0.id == id
				}),
				let window = view.window
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = prompt.title
		alert.informativeText =
			"Review these saved instructions before inserting them into the draft."
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
		alert.accessoryView = scrollView
		alert.addButton(withTitle: "Insert into Draft")
		alert.addButton(withTitle: "Edit…")
		alert.addButton(withTitle: "Close")
		context.selectedPromptID = id
		onUpdate?(context)
		rebuild()
		let generation = selectionGeneration
		let insertPrompt = makePromptInsertionReceiver(id: id)
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard let self, self.selectionGeneration == generation
			else
			{
				return
			}
			if response == .alertFirstButtonReturn
			{
				insertPrompt()
			}
			else if response == .alertSecondButtonReturn
			{
				self.editPrompt(prompt)
			}
		}
	}

	@objc private func selectSkill(_ sender: NSPopUpButton)
	{
		let key = sender.selectedItem?.representedObject as? String ?? ""
		context.selectedSkill = availableSkills.first
		{
			($0.path ?? $0.name) == key
		}
		onUpdate?(context)
		rebuild()
	}

	@objc private func selectModel(_ sender: NSPopUpButton)
	{
		let id = sender.selectedItem?.representedObject as? String ?? ""
		context.modelPreference = ProjectModelPreference(
			modelID: id.isEmpty ? nil : id,
			effort: context.modelPreference?.effort
		)
		onUpdate?(context)
		rebuild()
	}

	@objc private func selectEffort(_ sender: NSPopUpButton)
	{
		let value = sender.selectedItem?.representedObject as? String ?? ""
		context.modelPreference = ProjectModelPreference(
			modelID: context.modelPreference?.modelID,
			effort: value.isEmpty ? nil : value
		)
		onUpdate?(context)
		rebuild()
	}

	@objc private func toggleProjectPreferences(_ sender: NSButton)
	{
		context.modelPreference =
			sender.state == .on
				? ProjectModelPreference(
					modelID: nil,
					effort: nil
				) : nil
		onUpdate?(context)
		rebuild()
	}

	@objc private func openBookmark(_ sender: NSButton)
	{
		guard let id = sender.identifier?.rawValue,
				let bookmark = context.bookmarks.first(where:
				{
					$0.id == id
				})
		else
		{
			return
		}
		onOpenBookmark?(bookmark)
	}

	var onOpenBookmark: ((ConversationBookmark) -> Void)?
}
