import AppKit

extension NavigationViewController
{
	func confirmDeleteTask(
		_ thread: ThreadSummary,
		completion: ((String) -> Void)? = nil
	)
	{
		guard canManageTask(thread.id), let window = view.window, window.attachedSheet == nil
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
		panel.beginSheet(in: window)
		{
			[weak self, panel] response in
			panel.orderOut(nil)
			guard response == .OK, let self, modalScope == capturedScope,
					view.window === window
			else
			{
				return
			}
			guard canManageTask(capturedThreadID)
			else
			{
				presentTaskManagementUnavailable(
					threadID: capturedThreadID,
					in: window
				)
				return
			}
			complete?(capturedThreadID)
		}
	}

	func editProject(
		_ project: URL,
		completion: ((URL, String) -> Void)? = nil
	)
	{
		guard let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}
		projectInfoPopover.performClose(nil)
		let dialog = ProjectRenameViewController()
		_ = dialog.view
		dialog.input.field.stringValue = displayName(for: project)
		let panel = ProjectRenamePanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.title = "Rename project"
		panel.contentViewController = dialog
		dialog.view.layoutSubtreeIfNeeded()
		panel.setContentSize(dialog.view.fittingSize)
		panel.initialFirstResponder = dialog.input.field
		panel.defaultButtonCell = dialog.saveButton.cell as? NSButtonCell
		panel.onSave =
		{
			[weak dialog] in dialog?.saveButton.performClick(nil)
		}
		dialog.onDecision =
		{
			[weak panel] in panel?.finish($0)
		}
		let capturedScope = modalScope
		let complete = completion ?? onRenameProject
		panel.beginSheet(in: window)
		{
			[weak self, panel, dialog] response in
			panel.orderOut(nil)
			guard response == .OK, self?.modalScope == capturedScope
			else
			{
				return
			}
			complete?(
				project,
				dialog.input.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}
		dialog.input.field.selectText(nil)
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
			value: thread.displayTitle,
			accessibilityLabel: "Conversation name",
			actionTitle: "Rename",
			requiredThreadID: thread.id
		)
		{
			[weak self] value in
			guard let self, canManageTask(thread.id)
			else
			{
				self?.presentTaskManagementUnavailable(
					threadID: thread.id,
					in: window
				)
				return
			}
			complete?(value)
		}
	}

	func presentRenameTask(_ thread: ThreadSummary)
	{
		guard canManageTask(thread.id), let window = view.window, window.attachedSheet == nil
		else
		{
			return
		}
		let capturedThreadID = thread.id
		let complete = onRenameTask
		presentTextEntrySheet(
			in: window,
			title: "Rename Conversation",
			value: thread.displayTitle,
			accessibilityLabel: "Conversation name",
			actionTitle: "Rename"
		)
		{
			[weak self] value in
			guard let self, canManageTask(capturedThreadID)
			else
			{
				self?.presentTaskManagementUnavailable(
					threadID: capturedThreadID,
					in: window
				)
				return
			}
			complete?(capturedThreadID, value)
		}
	}

	private func presentTaskManagementUnavailable(
		threadID: String,
		in window: NSWindow
	)
	{
		guard view.window === window, window.attachedSheet == nil
		else
		{
			return
		}
		let alert = NSAlert()
		alert.messageText = "This task can no longer be changed."
		let execution = renderedPresentation?.threadExecutions[threadID]
		if execution?.outcomeUncertain == true
		{
			alert.informativeText = "Its outcome is unknown. Refresh this task before changing it."
		}
		else if execution?.state.isBusy == true
		{
			alert.informativeText = "This task is still running. Wait for it to finish."
		}
		else
		{
			alert.informativeText = "Refresh and try again."
		}
		alert.addButton(withTitle: "OK")
		alert.beginSheetModal(for: window)
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
		let prompt = DesktopTextEntryPrompt(
			title: title,
			detail: informativeText,
			actionTitle: actionTitle,
			fields: [DesktopTextEntryPrompt.Field(
				value: value,
				placeholder: placeholder,
				accessibilityLabel: accessibilityLabel
			)],
			layout: .single
		)
		let capturedScope = modalScope
		prompt.beginSheet(in: window)
		{
			[weak self] values in
			guard let value = values?.first, self?.modalScope == capturedScope,
					requiredThreadID == nil || self?.selectedThreadID == requiredThreadID
			else
			{
				return
			}
			completion(value)
		}
	}
}
