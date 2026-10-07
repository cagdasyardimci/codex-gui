import AppKit

extension NavigationViewController
{
	func focusSearch()
	{
		showSearch()
		searchField.window?.makeFirstResponder(searchField)
	}

	func showSearch()
	{
		_ = view
		projectActionsPopover.performClose(nil)
		projectInfoPopover.performClose(nil)
		if !searchPopover.isShown
		{
			searchPopover.show(
				relativeTo: searchButton.bounds,
				of: searchButton,
				preferredEdge: .maxX
			)
		}
	}

	@objc func toggleSearch()
	{
		if searchPopover.isShown
		{
			searchPopover.performClose(nil)
			projectInfoPopover.performClose(nil)
		}
		else
		{
			focusSearch()
		}
	}

	func controlTextDidChange(_ obj: Notification)
	{
		filterThreads()
	}

	func filterThreads()
	{
		let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		visibleThreads = threads.filter
		{
			thread in
			guard !query.isEmpty
			else
			{
				return true
			}
			let searchableText = [thread.name, thread.preview, thread.id].compactMap
			{
				$0
			}
			return searchableText.contains
			{
				$0.localizedCaseInsensitiveContains(query)
			}
		}
		rebuildSidebarItems()
		searchButton.contentTintColor = query.isEmpty ? .secondaryLabelColor : .controlAccentColor
		searchButton.toolTip = query.isEmpty ? "Search conversation titles and previews" : query
		emptyLabel.stringValue = query.isEmpty ? "No projects." : "No matching conversations."
		emptyLabel.isHidden = query.isEmpty ? !sidebarItems.isEmpty : !visibleThreads.isEmpty
		updateManagementButtons()
	}

	private func rebuildSidebarItems()
	{
		sidebarItems = NavigationSidebarItemsBuilder.build(
			recentProjects: recentProjects,
			currentProject: currentProject,
			pinnedProjectPaths: pinnedProjectPaths,
			visibleThreads: visibleThreads,
			isCurrentProjectCollapsed: isCurrentProjectCollapsed,
			projectTaskLimit: projectTaskLimit
		)
		updatingSidebarSelection = true
		defer
		{
			updatingSidebarSelection = false
		}
		chatsTable.reloadData()
		let selectedIndex =
			sidebarItems.firstIndex
				{
					item in
					if case .thread(let thread) = item
					{
						return thread.id == selectedThreadID
					}
					return false
				}
				?? sidebarItems.firstIndex
				{
					item in
					if case .project(let project) = item
					{
						return project == currentProject
					}
					return false
				}
		if let selectedIndex
		{
			chatsTable.selectRowIndexes(
				IndexSet(integer: selectedIndex),
				byExtendingSelection: false
			)
		}
		else
		{
			chatsTable.deselectAll(nil)
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		sidebarItems.count
	}

	func tableView(
		_ tableView: NSTableView,
		viewFor tableColumn: NSTableColumn?,
		row: Int
	) -> NSView?
	{
		guard sidebarItems.indices.contains(row)
		else
		{
			return nil
		}
		if case .showMore = sidebarItems[row]
		{
			return makeShowMoreCell()
		}
		if case .project(let project) = sidebarItems[row]
		{
			return projectCell(
				in: tableView,
				project: project
			)
		}
		guard case .thread(let thread) = sidebarItems[row]
		else
		{
			return nil
		}
		return taskCell(
			in: tableView,
			thread: thread
		)
	}

	private func makeShowMoreCell() -> NSTableCellView
	{
		let cell = NSTableCellView(frame: .zero)
		let button = NSButton(
			title: "Show more",
			target: self,
			action: #selector(showMoreTasks)
		)
		button.isBordered = false
		button.contentTintColor = .secondaryLabelColor
		button.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(button)
		NSLayoutConstraint.activate([
			button.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor,
				constant: 26
			),
			button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			button.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
		])
		return cell
	}

	private func taskCell(
		in tableView: NSTableView,
		thread: ThreadSummary
	) -> TaskSidebarCellView
	{
		let identifier = NSUserInterfaceItemIdentifier("conversationTitle")
		let cell = tableView.makeView(
			withIdentifier: identifier,
			owner: self
		)
			as? TaskSidebarCellView ?? TaskSidebarCellView(frame: .zero)
		cell.identifier = identifier
		cell.setActionsEnabled(canManageSidebarTasks)
		cell.onArchive =
		{
			[weak self] in self?.onArchiveTask?(thread.id)
		}
		cell.onDelete =
		{
			[weak self] in self?.confirmDeleteTask(thread)
		}

		let execution = renderedPresentation?.threadExecutions[thread.id]
		let isActiveTask = execution != nil
		let isTurnRunning = execution?.state == .running && execution?.outcomeUncertain != true
		cell.setTurnRunning(isTurnRunning)
		let isUnread = unreadThreadIDs.contains(thread.id)
		cell.setUnread(isUnread && !isTurnRunning)
		let showsInlineStatus =
			isActiveTask && !isTurnRunning
				&& (execution?.state != .completed || execution?.outcomeUncertain == true)
		let name = thread.name ?? thread.preview ?? thread.id
		let state = execution?.title ?? "Running"
		cell.textField?.stringValue =
			showsInlineStatus ? "●  \(name) · \(state)" : name
		cell.textField?.textColor = showsInlineStatus ? activeTaskColor : .labelColor
		cell.textField?.toolTip = nil
		let project = thread.cwd.isEmpty ? currentProject : URL(fileURLWithPath: thread.cwd)
		cell.hoverCard = TaskHoverCard(
			title: name,
			projectName: project.map
			{
				displayName(for: $0)
			} ?? "",
			updatedAt: thread.updatedAt
		)
		cell.textField?.setAccessibilityIdentifier("conversation-" + thread.id)
		cell.setAccessibilityLabel(
			isUnread ? "Unread result, open chat \(name)"
				: isActiveTask ? "\(state) task, open chat \(name)" : "Open chat \(name)"
		)
		return cell
	}

	private func projectCell(
		in tableView: NSTableView,
		project: URL
	) -> NSTableCellView
	{
		let identifier = NSUserInterfaceItemIdentifier("projectTitle")
		let cell =
			tableView.makeView(
				withIdentifier: identifier,
				owner: self
			) as? ProjectSidebarCellView
			?? ProjectSidebarCellView(frame: .zero)
		cell.identifier = identifier
		cell.render(
			project: project,
			name: displayName(for: project),
			isCurrent: project == currentProject,
			isExpanded: project == currentProject && !isCurrentProjectCollapsed,
			isPinned: pinnedProjectPaths.contains(projectKey(for: project)),
			canStartChat: canStartProjectChat
		)
		cell.onShowInfo =
		{
			[weak self] _ in self?.showProjectInfo(project)
		}
		cell.onNewChat =
		{
			[weak self] in
			guard let self, self.canStartProjectChat
			else
			{
				return
			}
			self.projectInfoPopover.performClose(nil)
			self.projectActionsPopover.performClose(nil)
			self.searchPopover.performClose(nil)
			self.onNewChatInProject?(project)
		}
		return cell
	}

	func tableView(
		_ tableView: NSTableView,
		rowViewForRow row: Int
	) -> NSTableRowView?
	{
		let rowView = ConversationSidebarRowView()
		if sidebarItems.indices.contains(row), case .project(let project) = sidebarItems[row]
		{
			rowView.isCurrentProject = project == currentProject
		}
		else
		{
			rowView.isTaskRow = true
		}
		return rowView
	}

	func tableViewSelectionDidChange(_ notification: Notification)
	{
		guard !updatingSidebarSelection
		else
		{
			return
		}
		let row = chatsTable.selectedRow
		guard sidebarItems.indices.contains(row)
		else
		{
			return
		}
		switch sidebarItems[row]
		{
		case .project(let project):
			if NSApp.currentEvent?.type == .keyDown
			{
				activateProject(project)
			}
		case .showMore:
			break
		case .thread(let thread):
			if thread.id != selectedThreadID
			{
				onSelectThread?(thread.id)
			}
		}
	}

	@objc func sidebarClicked()
	{
		let row = chatsTable.clickedRow
		guard sidebarItems.indices.contains(row), case .project(let project) = sidebarItems[row]
		else
		{
			return
		}
		activateProject(project)
	}

	func activateProject(_ project: URL)
	{
		if project == currentProject
		{
			isCurrentProjectCollapsed.toggle()
			projectTaskLimit = 5
			filterThreads()
		}
		else
		{
			onSelectRecentProject?(project)
		}
	}

	@objc func showMoreTasks()
	{
		guard !isCurrentProjectCollapsed, currentProject != nil,
				sidebarItems.contains(where:
				{
					if case .showMore = $0
					{
						return true
					}
					return false
				})
		else
		{
			return
		}
		projectTaskLimit += 10
		filterThreads()
	}

	func tableView(
		_ tableView: NSTableView,
		shouldSelectRow row: Int
	) -> Bool
	{
		guard sidebarItems.indices.contains(row)
		else
		{
			return false
		}
		if case .showMore = sidebarItems[row]
		{
			return false
		}
		return true
	}

	private var activeTaskColor: NSColor
	{
		switch activeExecutionState
		{
		case .awaitingApproval, .awaitingAnswer: .systemOrange
		case .failed, .disconnected: .systemRed
		case .completed: .systemGreen
		case .stopping, .stopped: .secondaryLabelColor
		case .running, .ready, nil: .controlAccentColor
		}
	}
}
