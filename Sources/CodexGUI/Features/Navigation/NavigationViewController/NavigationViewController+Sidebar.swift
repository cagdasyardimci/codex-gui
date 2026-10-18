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
		emptyLabel.isHidden = query.isEmpty ? !sidebarItems.isEmpty
			: !visibleThreads.isEmpty || pinnedTasks.contains
			{
				taskMatchesSearch($0)
			}
		updateManagementButtons()
	}

	private func rebuildSidebarItems()
	{
		sidebarItems = NavigationSidebarItemsBuilder.build(
			recentProjects: recentProjects,
			currentProject: currentProject,
			pinnedProjectPaths: pinnedProjectPaths,
			visibleThreads: visibleThreads,
			pinnedTasks: pinnedTasks.filter
			{
				taskMatchesSearch($0)
			},
			isCurrentProjectCollapsed: isCurrentProjectCollapsed,
			projectTaskLimit: projectTaskLimit,
			removedProjectPaths: removedProjectPaths
		)
		projectsHeader?.isHidden = sidebarItems.contains
		{
			if case .sectionHeader = $0
			{
				return true
			}
			return false
		}
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
					if case .pinnedThread(let thread) = item
					{
						return thread.id == selectedThreadID
					}
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

	func taskContextMenu(for row: Int) -> NSMenu?
	{
		guard sidebarItems.indices.contains(row)
		else
		{
			return nil
		}
		switch sidebarItems[row]
		{
		case .thread, .pinnedThread:
			let cell = chatsTable.view(
				atColumn: 0,
				row: row,
				makeIfNecessary: true
			)
				as? TaskSidebarCellView
			return cell?.makeContextMenu()
		case .project(let project): return projectContextMenu(project)
		case .sectionHeader, .showMore: return nil
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int
	{
		sidebarItems.count
	}

	func tableView(
		_ tableView: NSTableView,
		heightOfRow row: Int
	) -> CGFloat
	{
		if sidebarItems.indices.contains(row), case .sectionHeader = sidebarItems[row]
		{
			return NavigationSidebarLayout.sectionRowHeight(at: row)
		}
		return NavigationSidebarLayout.rowHeight
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
		if case .sectionHeader(let title) = sidebarItems[row]
		{
			return makeSectionHeader(
				title: title,
				row: row
			)
		}
		if case .pinnedThread(let thread) = sidebarItems[row]
		{
			return taskCell(
				in: tableView,
				thread: thread,
				isPinnedRow: true
			)
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

	private func makeSectionHeader(
		title: String,
		row: Int
	) -> NSTableCellView
	{
		let cell = NSTableCellView(frame: .zero)
		let header: NSView
		if title == "Projects"
		{
			header = makeProjectsHeader(actionsButton: NSButton())
		}
		else
		{
			let caption = SidebarTextField(labelWithString: title)
			caption.font = AppKitFontResolver.font(TypographyTokens.Sidebar.section)
			caption.textColor = AppKitColorTokens.secondaryText
			cell.textField = caption
			header = makeSidebarHeading([caption, NSView()])
		}
		cell.addSubview(header)
		header.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
			header.topAnchor.constraint(
				equalTo: cell.topAnchor,
				constant: NavigationSidebarLayout.sectionTopInset(at: row)
			),
		])
		return cell
	}

	private func makeShowMoreCell() -> NSTableCellView
	{
		let cell = NSTableCellView(frame: .zero)
		let label = SidebarTextField(labelWithString: "Show more")
		label.font = AppKitFontResolver.interfaceFont(
			ofSize: 14,
			weight: 400
		)
		label.textColor = AppKitColorTokens.secondaryText
		label.setAccessibilityElement(false)
		label.translatesAutoresizingMaskIntoConstraints = false
		cell.textField = label
		cell.addSubview(label)

		let button = NSButton(
			title: "",
			target: self,
			action: #selector(showMoreTasks)
		)
		button.isBordered = false
		button.setAccessibilityLabel("Show more")
		button.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(button)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor,
				constant: NavigationSidebarLayout.projectTitleInset
			),
			label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
			button.leadingAnchor.constraint(equalTo: label.leadingAnchor),
			button.trailingAnchor.constraint(equalTo: label.trailingAnchor),
			button.topAnchor.constraint(equalTo: cell.topAnchor),
			button.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
		])
		return cell
	}

	private func taskCell(
		in tableView: NSTableView,
		thread: ThreadSummary,
		isPinnedRow: Bool = false
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
		cell.isPinned = pinnedTasks.contains
		{
			$0.id == thread.id
		}
		cell.setPinnedRow(isPinnedRow)
		cell.onRename =
		{
			[weak self] in self?.presentRenameTask(thread)
		}
		cell.onTogglePin =
		{
			[weak self] in self?.onToggleTaskPin?(thread)
		}
		cell.onMarkUnread =
		{
			[weak self] in self?.markTaskUnread(thread.id)
		}
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
		let name = thread.displayTitle
		let state = execution?.title ?? "Running"
		cell.textField?.stringValue =
			showsInlineStatus ? "●  \(name) · \(state)" : name
		cell.textField?
			.textColor = showsInlineStatus ? taskColor(for: execution?.state) : AppKitColorTokens
			.sidebarText
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
			[weak self] cell in
			guard let menu = self?.projectContextMenu(project)
			else
			{
				return
			}
			menu.popUp(
				positioning: nil,
				at: NSPoint(
					x: cell.bounds.maxX,
					y: cell.bounds.maxY
				),
				in: cell
			)
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
			rowView.isTaskRow = sidebarItems.indices.contains(row) &&
			{
				if case .sectionHeader = sidebarItems[row]
				{
					return false
				}
				return true
			}()
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
		case .showMore, .sectionHeader:
			break
		case .pinnedThread(let thread):
			markTaskRead(thread.id)
			if thread.id != selectedThreadID
			{
				onSelectPinnedTask?(thread)
			}
		case .thread(let thread):
			markTaskRead(thread.id)
			if thread.id != selectedThreadID
			{
				onSelectThread?(thread.id)
			}
		}
	}

	@objc func sidebarClicked()
	{
		let row = chatsTable.clickedRow
		guard sidebarItems.indices.contains(row)
		else
		{
			return
		}
		switch sidebarItems[row]
		{
		case .project(let project): activateProject(project)
		case .thread(let thread), .pinnedThread(let thread):
			markTaskRead(thread.id)
			filterThreads()
		case .sectionHeader, .showMore: break
		}
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
		switch sidebarItems[row]
		{
		case .showMore, .sectionHeader: return false
		default: break
		}
		return true
	}

	private func taskMatchesSearch(_ thread: ThreadSummary) -> Bool
	{
		let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		return query.isEmpty || [thread.name, thread.preview, thread.id].compactMap
		{
			$0
		}
		.contains
		{
			$0.localizedCaseInsensitiveContains(query)
		}
	}

	func markTaskUnread(_ threadID: String)
	{
		manuallyUnreadThreadIDs.insert(threadID)
		unreadThreadIDs.insert(threadID)
		filterThreads()
	}

	private func markTaskRead(_ threadID: String)
	{
		manuallyUnreadThreadIDs.remove(threadID)
		unreadThreadIDs.remove(threadID)
	}

	private func taskColor(for state: ExecutionState?) -> NSColor
	{
		switch state
		{
		case .awaitingApproval, .awaitingAnswer: .systemOrange
		case .failed, .disconnected: .systemRed
		case .completed: .systemGreen
		case .stopping, .stopped: .secondaryLabelColor
		case .running, .ready, nil: .controlAccentColor
		}
	}
}
