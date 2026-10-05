import AppKit

extension NavigationViewController
{
	func confirmDeleteTask(
		_ thread: ThreadSummary,
		completion: ((String) -> Void)? = nil
	)
	{
		guard canManageSidebarTasks, let window = view.window
		else
		{
			return
		}
		let name = thread.name ?? thread.preview ?? thread.id
		let alert = NSAlert()
		alert.messageText = "Delete task permanently?"
		alert.informativeText = "The conversation “\(name)” will be permanently deleted. "
			+ "This cannot be undone."
		alert.alertStyle = .warning
		alert.addButton(withTitle: "Cancel")
		alert.addButton(withTitle: "Delete Permanently")
		alert.buttons.last?.hasDestructiveAction = true
		let capturedScope = modalScope
		let complete = completion ?? onDeleteTask
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertSecondButtonReturn, self?.modalScope == capturedScope,
					self?.canManageSidebarTasks == true
			else
			{
				return
			}
			complete?(thread.id)
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
