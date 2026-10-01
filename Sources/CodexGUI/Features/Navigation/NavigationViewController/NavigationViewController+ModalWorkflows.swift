import AppKit

extension NavigationViewController
{
	func confirmDeleteTask(_ thread: ThreadSummary)
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
		let complete = onDeleteTask
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
		let alert = NSAlert()
		alert.messageText = "Edit Project"
		alert.informativeText =
			"Set a local display name. The repository folder remains at \(project.path)."
		let field = NSTextField(string: projectDisplayNames[projectKey(for: project)] ?? "")
		field.placeholderString = project.lastPathComponent
		field.frame = NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 24
		)
		field.setAccessibilityLabel("Local project display name")
		alert.accessoryView = field
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		let capturedScope = modalScope
		let complete = onRenameProject
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, self?.modalScope == capturedScope
			else
			{
				return
			}
			complete?(
				project,
				field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
		let alert = NSAlert()
		alert.messageText = "New Task Checkout"
		alert.informativeText = "The task starts from the source repository's committed HEAD."
		let field = NSTextField(string: "")
		field.placeholderString = "Task name"
		field.frame = NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 24
		)
		field.setAccessibilityLabel("Task name")
		alert.accessoryView = field
		alert.addButton(withTitle: "Create Task")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		let capturedScope = modalScope
		let complete = onCreateTask
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, self?.modalScope == capturedScope
			else
			{
				return
			}
			complete?(field.stringValue)
		}
	}

	@objc func renameThread()
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
		let alert = NSAlert()
		alert.messageText = "Rename Conversation"
		let field = NSTextField(string: thread.name ?? thread.preview ?? "")
		field.frame = NSRect(
			x: 0,
			y: 0,
			width: 320,
			height: 24
		)
		field.setAccessibilityLabel("Conversation name")
		alert.accessoryView = field
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		let capturedScope = modalScope
		let complete = onRenameThread
		alert.beginSheetModal(for: window)
		{
			[weak self] response in
			guard response == .alertFirstButtonReturn, self?.modalScope == capturedScope,
					self?.selectedThreadID == thread.id
			else
			{
				return
			}
			complete?(field.stringValue)
		}
	}
}
