import AppKit

extension NavigationViewController
{
	func makeTaskSelectionRow() -> NSStackView
	{
		taskPicker.target = self
		taskPicker.autoenablesItems = false
		taskPicker.action = #selector(selectWorkspace)
		taskPicker.setAccessibilityLabel("Selected task checkout")
		taskPicker.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		taskPicker.cell?.lineBreakMode = .byTruncatingTail

		taskPicker.font = .systemFont(ofSize: 11)
		let taskRow = AppKitLayout.horizontalStack([taskPicker])

		return taskRow
	}

	func makeActiveTaskRow() -> NSStackView
	{
		returnToTaskButton.target = self
		returnToTaskButton.action = #selector(returnToActiveTask)
		returnToTaskButton.setAccessibilityLabel("Return to active task")

		returnToTaskButton.size = .mini

		return AppKitLayout.horizontalStack([returnToTaskButton])
	}

	func renderTaskStatus(_ snapshot: NavigationPresentation)
	{
		returnToTaskButton.isEnabled =
			snapshot.activeThreadID != nil && snapshot.activeThreadID != snapshot.selectedThreadID
		returnToTaskButton.isHidden = !returnToTaskButton.isEnabled
		projectActionsButton.contentTintColor = AppKitColorTokens.secondaryText
		projectActionsButton.toolTip =
			sidebarPreferences.organization == .oneList ? "New chat" : "Add new project"
	}

	func renderTaskWorkspaces(
		_ snapshot: NavigationPresentation,
		rebuildMenu: Bool
	)
	{
		if rebuildMenu
		{
			rebuildWorkspaceMenu(snapshot)
		}
		selectedWorkspaceID = snapshot.selectedTaskWorkspaceID
		restoreWorkspaceSelection()
	}

	private func rebuildWorkspaceMenu(_ snapshot: NavigationPresentation)
	{
		taskPicker.removeAllItems()
		taskPicker.addItem(withTitle: "Source checkout")
		taskPicker.item(at: 0)?.representedObject = NSNull()
		let taskActions = NSMenu(title: "Task Actions")
		taskActions.autoenablesItems = false
		for workspace in snapshot.taskWorkspaces
		{
			appendWorkspaceChoice(workspace)
			appendWorkspaceAction(
				workspace,
				to: taskActions
			)
		}
		appendWorkspaceManagementItems(
			snapshot,
			taskActions: taskActions
		)
	}

	private func appendWorkspaceChoice(_ workspace: TaskWorkspaceChoice)
	{
		let statePrefix: String
		if let executionState = workspace.executionState, executionState.isBusy
		{
			statePrefix = "● \(executionState.title) · "
		}
		else
		{
			statePrefix = ""
		}
		let issue = workspace.issue.map
		{
			" · \($0)"
		} ?? ""
		taskPicker.addItem(withTitle: "\(statePrefix)\(workspace.title)\(issue)")
		taskPicker.lastItem?.representedObject = workspace.id
		taskPicker.lastItem?.isEnabled =
			workspace.phase == .active
				&& (workspace.issue == nil
					|| workspace.issue == TaskWorkspaceRecoveryKind.removalInterrupted.rawValue)
		let sourceStateNote = workspace.sourceWasDirty
			? "\nSource had uncommitted changes at creation." : ""
		taskPicker.lastItem?.toolTip =
			"\(workspace.checkoutPath)\n\(workspace.branch)" + sourceStateNote
	}

	private func appendWorkspaceAction(
		_ workspace: TaskWorkspaceChoice,
		to taskActions: NSMenu
	)
	{
		if workspace.phase == .active
		{
			let item = taskActions.addItem(
				withTitle: "Remove checkout: \(workspace.title)",
				action: #selector(removeWorkspace(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = workspace.id
			item.isEnabled = workspace.canRemoveCheckout
		}
		else if workspace.phase == .preparing
		{
			let item = taskActions.addItem(
				withTitle: "Cancel incomplete creation: \(workspace.title)",
				action: #selector(cancelWorkspaceCreation(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = workspace.id
		}
	}

	private func appendWorkspaceManagementItems(
		_ snapshot: NavigationPresentation,
		taskActions: NSMenu
	)
	{
		taskPicker.menu?.addItem(.separator())
		let create = taskPicker.menu?.addItem(
			withTitle: "New Task Checkout…",
			action: #selector(createTask),
			keyEquivalent: ""
		)
		create?.target = self
		create?.isEnabled = !snapshot.recentProjects.isEmpty || snapshot.projectPath != nil
		if !taskActions.items.isEmpty
		{
			let actions = NSMenuItem(
				title: "Task Actions",
				action: nil,
				keyEquivalent: ""
			)
			actions.submenu = taskActions
			taskPicker.menu?.addItem(actions)
		}
	}

	@objc func selectWorkspace()
	{
		onSelectWorkspace?(taskPicker.selectedItem?.representedObject as? UUID)
	}

	private func restoreWorkspaceSelection()
	{
		let index =
			selectedWorkspaceID.flatMap
				{
					id in
					taskPicker.itemArray.firstIndex
					{
						($0.representedObject as? UUID) == id
					}
				} ?? 0
		taskPicker.selectItem(at: index)
	}

	@objc private func removeWorkspace(_ sender: NSMenuItem)
	{
		restoreWorkspaceSelection()
		if let id = sender.representedObject as? UUID
		{
			onRemoveWorkspace?(id)
		}
	}

	@objc private func cancelWorkspaceCreation(_ sender: NSMenuItem)
	{
		restoreWorkspaceSelection()
		if let id = sender.representedObject as? UUID
		{
			onCancelWorkspaceCreation?(id)
		}
	}

	@objc private func createTask()
	{
		restoreWorkspaceSelection()
		presentNewTask()
	}

	@objc func returnToActiveTask()
	{
		projectActionsPopover.performClose(nil)
		onReturnToActiveTask?()
	}
}
