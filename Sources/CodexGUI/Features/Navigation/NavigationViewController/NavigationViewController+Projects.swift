import AppKit

extension NavigationViewController
{
	func projectContextMenu(_ project: URL) -> NSMenu
	{
		let pin = onToggleProjectPin
		let rename = onRenameProject
		let archive = onArchiveProjectChats
		let remove = onRemoveProject
		return ProjectSidebarContextMenu(
			isPinned: pinnedProjectPaths.contains(projectKey(for: project)),
			onTogglePin: pin.map
			{
				callback in
				{
					callback(project)
				}
			},
			onRename: rename == nil ? nil :
			{
				[weak self] in self?.editProject(
					project,
					completion: rename
				)
			},
			onReveal:
			{
				NSWorkspace.shared.activateFileViewerSelecting([project])
			},
			onArchive: canManageSidebarTasks ? archive
				.map
				{
					callback in
					{
						callback(project)
					}
				} : nil,
			onRemove: remove.map
			{
				callback in
				{
					callback(project)
				}
			}
		)
	}

	func renderRecentProjects(_ projects: [URL])
	{
		recentProjectsButton.removeAllItems()
		recentProjectsButton.addItem(withTitle: "Recent…")
		recentProjectsButton.item(at: 0)?.isEnabled = false
		for project in projects
		{
			recentProjectsButton.addItem(withTitle: displayName(for: project))
			recentProjectsButton.lastItem?.representedObject = project
			recentProjectsButton.lastItem?.toolTip = project.path
		}
		recentProjectsButton.selectItem(at: 0)
	}

	@objc func toggleProjectActions(_ sender: NSButton? = nil)
	{
		if projectActionsPopover.isShown
		{
			projectActionsPopover.performClose(nil)
		}
		else
		{
			searchPopover.performClose(nil)
			resizeProjectActionsPopover()
			let anchor = sender ?? projectActionsButton
			projectActionsPopover.show(
				relativeTo: anchor.bounds,
				of: anchor,
				preferredEdge: .maxX
			)
			projectActionsPopover.contentViewController?.view.window?.makeFirstResponder(taskPicker)
		}
	}

	func resizeProjectActionsPopover()
	{
		guard let content = projectActionsPopover.contentViewController?.view
		else
		{
			return
		}
		projectActionsPopover.contentSize = NSSize(
			width: 280,
			height: max(
				96,
				content.fittingSize.height
			)
		)
	}

	func projectKey(for project: URL) -> String
	{
		project.standardizedFileURL.resolvingSymlinksInPath().path
	}

	func displayName(for project: URL) -> String
	{
		projectDisplayNames[projectKey(for: project)] ?? project.lastPathComponent
	}

	func showProjectInfo(_ project: URL)
	{
		if projectInfoPopover.isShown && projectInfoProject == project
		{
			projectInfoPopover.performClose(nil)
			return
		}
		projectActionsPopover.performClose(nil)
		searchPopover.performClose(nil)
		projectInfoProject = project
		projectInfoView.onTogglePin =
		{
			[weak self] in self?.onToggleProjectPin?(project)
		}
		projectInfoView.onEditProject =
		{
			[weak self] in self?.editProject(project)
		}
		refreshProjectInfo()
		guard let row = projectRow(for: project)
		else
		{
			return
		}
		projectInfoPopover.show(
			relativeTo: chatsTable.rect(ofRow: row),
			of: chatsTable,
			preferredEdge: .maxX
		)
	}

	private func projectRow(for project: URL) -> Int?
	{
		sidebarItems.firstIndex
		{
			item in
			if case .project(let candidate) = item
			{
				return candidate == project
			}
			return false
		}
	}

	func refreshProjectInfo()
	{
		guard let project = projectInfoProject, let row = projectRow(for: project)
		else
		{
			projectInfoPopover.performClose(nil)
			return
		}
		let isCurrent = project == currentProject
		projectInfoView.render(
			project: project,
			name: displayName(for: project),
			isPinned: pinnedProjectPaths.contains(projectKey(for: project)),
			loadedTaskCount: isCurrent ? threads.count : nil,
			activeTaskCount: isCurrent ? currentProjectActiveTaskCount : nil
		)
		projectInfoPopover.contentSize = NSSize(
			width: 300,
			height: max(
				120,
				projectInfoView.fittingSize.height
			)
		)
		if projectInfoPopover.isShown
		{
			let rowRect = chatsTable.rect(ofRow: row)
			if chatsTable.visibleRect.intersects(rowRect)
			{
				projectInfoPopover.positioningRect = rowRect
			}
			else
			{
				projectInfoPopover.performClose(nil)
			}
		}
	}

	@objc func openProject()
	{
		projectActionsPopover.performClose(nil)
		onOpenProject?()
	}

	@objc func selectRecentProject()
	{
		guard let project = recentProjectsButton.selectedItem?.representedObject as? URL
		else
		{
			return
		}
		projectActionsPopover.performClose(nil)
		onSelectRecentProject?(project)
	}
}
