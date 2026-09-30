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
		DesktopTheme.stylePopup(taskPicker)
		taskPicker.font = .systemFont(ofSize: 11)
		let taskRow = AppKitLayout.horizontalStack([taskPicker])

		taskSummaryLabel.textColor = .secondaryLabelColor
		taskSummaryLabel.font = .systemFont(ofSize: 11)
		taskSummaryLabel.maximumNumberOfLines = 3
		taskSummaryLabel.lineBreakMode = .byWordWrapping
		taskSummaryLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		taskSummaryLabel.setAccessibilityLabel("Running task summary")
		return taskRow
	}

	func makeActiveTaskRow() -> NSStackView
	{
		activeTaskLabel.lineBreakMode = .byTruncatingTail
		activeTaskLabel.font = .systemFont(ofSize: 11)
		activeTaskLabel.setAccessibilityLabel("Active task status")

		returnToTaskButton.target = self
		returnToTaskButton.action = #selector(returnToActiveTask)
		returnToTaskButton.setAccessibilityLabel("Return to active task")
		DesktopTheme.styleButton(returnToTaskButton)
		returnToTaskButton.font = .systemFont(ofSize: 10)

		let activeTaskRow = AppKitLayout.horizontalStack([activeTaskLabel, returnToTaskButton])
		activeTaskLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		return activeTaskRow
	}

	func renderTaskStatus(_ snapshot: NavigationPresentation) -> ExecutionState?
	{
		let activeState =
			snapshot.activeExecutionState
				?? (snapshot.activeThreadID == nil && snapshot.executionState.isBusy
					? snapshot.executionState : nil)
		activeTaskLabel.stringValue = activeState.map
		{
			"Task: \($0.title)"
		} ?? ""
		activeTaskLabel.toolTip = snapshot.activeThreadID.flatMap
		{
			id in
			snapshot.threads.first(where:
				{
					$0.id == id
				}).flatMap
			{
				$0.name ?? $0.preview
			}
		}
		activeTaskLabel.superview?.isHidden = activeState == nil
		returnToTaskButton.isEnabled =
			snapshot.activeThreadID != nil && snapshot.activeThreadID != snapshot.selectedThreadID
		returnToTaskButton.isHidden = !returnToTaskButton.isEnabled
		archivedButton.state = snapshot.showingArchived ? .on : .off
		projectActionsButton.contentTintColor =
			snapshot
				.showingArchived || activeState != nil ? .controlAccentColor : .secondaryLabelColor
		projectActionsButton.toolTip =
			[
				"Project and conversation actions",
				activeTaskLabel.stringValue,
				taskSummaryLabel.stringValue,
			].filter
			{
				!$0.isEmpty
			}.joined(separator: "\n")
		return activeState
	}

	func renderTaskWorkspaces(_ snapshot: NavigationPresentation)
	{
		taskPicker.removeAllItems()
		taskPicker.addItem(withTitle: "Source checkout")
		taskPicker.item(at: 0)?.representedObject = NSNull()
		let taskActions = NSMenu(title: "Task Actions")
		taskActions.autoenablesItems = false
		for workspace in snapshot.taskWorkspaces
		{
			let state =
				workspace.executionState?.isBusy == true
					? "● \(workspace.executionState!.title) · " : ""
			let issue = workspace.issue.map
			{
				" · \($0)"
			} ?? ""
			taskPicker.addItem(withTitle: "\(state)\(workspace.title)\(issue)")
			taskPicker.lastItem?.representedObject = workspace.id
			taskPicker.lastItem?.isEnabled =
				workspace.phase == .active
					&& (workspace.issue == nil
						|| workspace.issue == TaskWorkspaceRecoveryKind.removalInterrupted.rawValue)
			taskPicker.lastItem?.toolTip =
				"\(workspace.checkoutPath)\n\(workspace.branch)"
					+
					(workspace
						.sourceWasDirty ? "\nSource had uncommitted changes at creation." : "")
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
		selectedWorkspaceID = snapshot.selectedTaskWorkspaceID
		restoreWorkspaceSelection()
		taskSummaryLabel.stringValue =
			[snapshot.taskStatusSummary, snapshot.taskWorkspaceMessage].compactMap
				{
					$0
				}
				.joined(separator: " · ")
		taskSummaryLabel.toolTip = taskSummaryLabel.stringValue
		taskSummaryLabel.isHidden = taskSummaryLabel.stringValue.isEmpty
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
