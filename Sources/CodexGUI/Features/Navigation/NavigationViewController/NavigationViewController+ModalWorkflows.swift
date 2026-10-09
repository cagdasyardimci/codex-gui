import AppKit

extension NavigationViewController
{
	func confirmDeleteTask(
		_ thread: ThreadSummary,
		completion: ((String) -> Void)? = nil
	)
	{
		guard canManageSidebarTasks, let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}
		let confirmation = TaskDeletionConfirmationView()
		let panel = TaskDeletionConfirmationPanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.title = "Delete task?"
		panel.contentViewController = confirmation
		confirmation.view.layoutSubtreeIfNeeded()
		panel.setContentSize(confirmation.view.fittingSize)
		panel.initialFirstResponder = confirmation.cancelButton
		panel.defaultButtonCell = confirmation.cancelButton.cell as? NSButtonCell
		confirmation.onDecision =
		{
			[weak panel] confirmed in
			panel?.finishDecision(confirmed)
		}

		let capturedScope = modalScope
		let capturedThreadID = thread.id
		let complete = completion ?? onDeleteTask
		window.beginSheet(panel)
		{
			[weak self, panel] response in
			panel.orderOut(nil)
			guard response == .OK, self?.modalScope == capturedScope,
					self?.canManageSidebarTasks == true
			else
			{
				return
			}
			complete?(capturedThreadID)
		}
	}

	func editProject(_ project: URL)
	{
		guard let window = view.window
		else
		{
			return
		}
		projectInfoPopover.performClose(nil)
		let complete = onRenameProject
		presentTextEntrySheet(
			in: window,
			title: "Edit Project",
			informativeText:
			"Set a local display name. The repository folder remains at \(project.path).",
			value: projectDisplayNames[projectKey(for: project)] ?? "",
			placeholder: project.lastPathComponent,
			accessibilityLabel: "Local project display name",
			actionTitle: "Save"
		)
		{
			value in
			complete?(
				project,
				value.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}
	}

	func presentNewTask()
	{
		guard let window = view.window
		else
		{
			return
		}
		projectActionsPopover.performClose(nil)
		let complete = onCreateTask
		presentTextEntrySheet(
			in: window,
			title: "New Task Checkout",
			informativeText: "The task starts from the source repository's committed HEAD.",
			value: "",
			placeholder: "Task name",
			accessibilityLabel: "Task name",
			actionTitle: "Create Task"
		)
		{
			value in complete?(value)
		}
	}

	@objc func renameThread()
	{
		presentRenameThread()
	}

	func presentRenameThread(completion: ((String) -> Void)? = nil)
	{
		guard renameButton.isEnabled, let window = view.window,
				let thread = threads.first(where:
				{
					$0.id == selectedThreadID
				})
		else
		{
			return
		}
		projectActionsPopover.performClose(nil)
		let complete = completion ?? onRenameThread
		presentTextEntrySheet(
			in: window,
			title: "Rename Conversation",
			value: thread.name ?? thread.preview ?? "",
			accessibilityLabel: "Conversation name",
			actionTitle: "Rename",
			requiredThreadID: thread.id
		)
		{
			value in complete?(value)
		}
	}

	func presentRenameTask(_ thread: ThreadSummary)
	{
		guard canManageSidebarTasks, let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}
		let capturedThreadID = thread.id
		let complete = onRenameTask
		presentTextEntrySheet(
			in: window,
			title: "Rename Conversation",
			value: thread.name ?? thread.preview ?? "",
			accessibilityLabel: "Conversation name",
			actionTitle: "Rename"
		)
		{
			[weak self] value in
			guard self?.canManageSidebarTasks == true
			else
			{
				return
			}
			complete?(capturedThreadID, value)
		}
	}

	private func presentTextEntrySheet(
		in window: NSWindow,
		title: String,
		informativeText: String = "",
		value: String,
		placeholder: String? = nil,
		accessibilityLabel: String,
		actionTitle: String,
		requiredThreadID: String? = nil,
		completion: @escaping (String) -> Void
	)
	{
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = informativeText
		let field = NSTextField(string: value)
		field.placeholderString = placeholder
		field.frame = NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 24
		)
		field.setAccessibilityLabel(accessibilityLabel)
		alert.accessoryView = field
		alert.addButton(withTitle: actionTitle)
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		let capturedScope = modalScope
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, self?.modalScope == capturedScope,
					requiredThreadID == nil || self?.selectedThreadID == requiredThreadID
			else
			{
				return
			}
			completion(field.stringValue)
		}
	}
}
