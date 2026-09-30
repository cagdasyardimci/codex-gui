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
			query.isEmpty
				|| [$0.name, $0.preview, $0.id].compactMap
				{
					$0
				}.contains
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
			visibleThreads: visibleThreads
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
		let identifier = NSUserInterfaceItemIdentifier("conversationTitle")
		let cell =
			tableView.makeView(
				withIdentifier: identifier,
				owner: self
			) as? NSTableCellView
			?? NSTableCellView()
		cell.identifier = identifier

		if cell.textField == nil
		{
			let label = NSTextField(labelWithString: "")
			label.font = .systemFont(ofSize: 14)
			label.lineBreakMode = .byTruncatingTail
			cell.addSubview(label)
			label.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				label.leadingAnchor.constraint(
					equalTo: cell.leadingAnchor,
					constant: 50
				),
				label.trailingAnchor.constraint(
					equalTo: cell.trailingAnchor,
					constant: -10
				),
				label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			])
			cell.textField = label
		}

		let isActiveTask = thread.id == activeThreadID
		let name = thread.name ?? thread.preview ?? thread.id
		let state = activeExecutionState?.title ?? "Running"
		cell.textField?.stringValue = isActiveTask ? "●  \(name) · \(state)" : name
		cell.textField?.textColor = isActiveTask ? activeTaskColor : .labelColor
		cell.textField?.toolTip = thread.preview
		cell.setAccessibilityLabel(
			isActiveTask ? "\(state) task, open chat \(name)" : "Open chat \(name)"
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
			if project != currentProject
			{
				onSelectRecentProject?(project)
			}
		case .thread(let thread):
			if thread.id != selectedThreadID
			{
				onSelectThread?(thread.id)
			}
		}
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
