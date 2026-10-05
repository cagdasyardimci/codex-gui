import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationViewControllerTests
{
	@Test func progressRingStopsWhenDetachedOrCellIsReused() throws
	{
		_ = NSApplication.shared
		let cell = TaskSidebarCellView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		))
		let window = NSWindow(
			contentRect: cell.frame,
			styleMask: [],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		cell.setTurnRunning(true)
		window.contentView?.addSubview(cell)
		cell.layoutSubtreeIfNeeded()
		let ringLayer = try #require(cell.progressRing.layer?.sublayers?.first)
		#expect(ringLayer.animation(forKey: "taskRotation") != nil)
		cell.removeFromSuperview()
		#expect(ringLayer.animation(forKey: "taskRotation") == nil)
		window.contentView?.addSubview(cell)
		#expect(ringLayer.animation(forKey: "taskRotation") != nil)
		cell.setTurnRunning(false)
		#expect(ringLayer.animation(forKey: "taskRotation") == nil)
		#expect(cell.progressRing.isHidden)
		cell.removeFromSuperview()
	}

	@Test func projectTasksExpandFiveThenTenInRecentOrder() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let project = URL(fileURLWithPath: "/tmp/paged-sidebar")
		controller.currentProject = project
		controller.threads = try (0 ..< 26).map
		{
			index in
			try #require(ThreadSummary(json: ["id": "task-\(index)", "updatedAt": Double(index)]))
		}
		controller.filterThreads()
		func taskIDs() -> [String]
		{
			controller.sidebarItems.compactMap
			{
				if case .thread(let thread) = $0
				{
					return thread.id
				}
				return nil
			}
		}
		#expect(taskIDs() == (21 ... 25).reversed().map
		{
			"task-\($0)"
		})
		#expect(controller.chatsTable.numberOfRows == 7)
		let cell = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 6
		))
		let button = try #require(cell.subviews.first as? NSButton)
		#expect(button.title == "Show more")
		button.performClick(nil)
		#expect(taskIDs().count == 15)
		controller.filterThreads()
		#expect(taskIDs().count == 15)
		controller.showMoreTasks()
		#expect(taskIDs().count == 25)
		controller.showMoreTasks()
		#expect(taskIDs().count == 26)
		#expect(controller.chatsTable.numberOfRows == 27)
		controller.activateProject(project)
		#expect(controller.chatsTable.numberOfRows == 1)
		controller.activateProject(project)
		#expect(taskIDs().count == 5)
	}

	@Test func projectCanCollapseWithoutChangingSelectedTask() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let project = URL(fileURLWithPath: "/tmp/sidebar").standardizedFileURL
			.resolvingSymlinksInPath()
		controller.currentProject = project
		controller.threads = [try #require(ThreadSummary(json: ["id": "task", "name": "Task"]))]
		controller.selectedThreadID = "task"
		controller.filterThreads()
		#expect(controller.chatsTable.numberOfRows == 2)
		let expanded = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 0
		)
			as? ProjectSidebarCellView)
		let expandedIcon = expanded.imageView?.image
		controller.activateProject(project)
		#expect(controller.chatsTable.numberOfRows == 1)
		#expect(controller.selectedThreadID == "task")
		#expect(controller.currentProject == project)
		let collapsed = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 0
		)
			as? ProjectSidebarCellView)
		#expect(collapsed.imageView?.image != expandedIcon)
		controller.filterThreads()
		#expect(controller.chatsTable.numberOfRows == 1)
		controller.activateProject(project)
		#expect(controller.chatsTable.numberOfRows == 2)
		#expect(controller.chatsTable.selectedRow == 1)
	}

	@Test func taskTitleScrollsOnceAndHoverCardUsesMetadataForItsOwnRow() async throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		controller.threads = [try #require(ThreadSummary(json: [
			"id": "hovered",
			"name": "A task title long enough to require truncation in the sidebar",
			"preview": "The original request should not be the hover card",
			"cwd": "/tmp/codex-gui"
		]))]
		controller.selectedThreadID = "another"
		controller.canManageSidebarTasks = true
		controller.filterThreads()
		let cell = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 0
		)
			as? TaskSidebarCellView)
		cell.frame = NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 400
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView?.addSubview(cell)
		window.makeKeyAndOrderFront(nil)
		defer
		{
			cell.removeFromSuperview()
			window.orderOut(nil)
		}
		cell.setTurnRunning(true)
		cell.layoutSubtreeIfNeeded()
		#expect(cell.progressRing.frame.maxX == cell.bounds.maxX - 4)
		#expect(cell.progressRing.alphaValue == 1)
		let label = try #require(cell.textField as? HoverScrollingTextField)
		let restingFrame = label.frame
		#expect(label.alignmentRect(forFrame: restingFrame).minX == 26)
		#expect(label.lineBreakMode == .byTruncatingTail)
		#expect(label.cell?.isScrollable == false)
		#expect(!label.allowsExpansionToolTips)
		let event = try #require(NSEvent.enterExitEvent(
			with: .mouseEntered,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
		cell.setTurnRunning(false)
		cell.setUnread(true)
		cell.mouseEntered(with: event)
		let hoveredFrame = label.frame
		#expect(hoveredFrame.width < restingFrame.width)
		#expect(cell.unreadDot.alphaValue == 0)
		#expect(cell.progressRing.alphaValue == 0)
		#expect(cell.archiveButton.superview?.alphaValue == 1)
		cell.setTurnRunning(true)
		#expect(cell.progressRing.alphaValue == 0)
		label.advanceScrolling(elapsed: 1.6)
		if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		{
			#expect(label.scrollOffset > 0)
			label.advanceScrolling(elapsed: 60)
			let finishedOffset = label.scrollOffset
			#expect(finishedOffset > 0)
			label.advanceScrolling(elapsed: 120)
			#expect(label.scrollOffset == finishedOffset)
			label.stringValue = label.stringValue
			#expect(label.scrollOffset == finishedOffset)
		}
		let panel = try #require(cell.hoverCard?.panel)
		#expect(panel.isVisible)
		#expect(panel.parent === window)
		#expect(panel.animationBehavior == .none)
		#expect(panel.ignoresMouseEvents)
		#expect(label.toolTip == nil)
		#expect(cell.hoverCard?.title == label.stringValue)
		#expect(cell.hoverCard?.projectName == "codex-gui")
		cell.layoutSubtreeIfNeeded()
		#expect(label.frame == hoveredFrame)
		var archived: String?
		controller.onArchiveTask =
		{
			archived = $0
		}
		cell.archiveButton.performClick(nil)
		#expect(archived == "hovered")
		#expect(controller.selectedThreadID == "another")
		cell.mouseExited(with: event)
		#expect(label.scrollOffset == 0)
		#expect(cell.progressRing.alphaValue == 1)
		#expect(cell.unreadDot.alphaValue == 1)
		#expect(cell.archiveButton.superview?.alphaValue == 0)
		#expect(cell.hoverCard?.panel == nil)
		#expect(!panel.isVisible)
		cell.layoutSubtreeIfNeeded()
		#expect(label.frame == restingFrame)
		label.stringValue = "Short"
		cell.mouseEntered(with: event)
		label.advanceScrolling(elapsed: 1.6)
		#expect(label.scrollOffset == 0)
		#expect(label.frame == hoveredFrame)
		#expect(cell.hoverCard?.panel != nil)
		NotificationCenter.default.post(
			name: NSWindow.didResignKeyNotification,
			object: window
		)
		#expect(cell.hoverCard?.panel == nil)
		#expect(cell.progressRing.alphaValue == 1)
	}

	@Test func streamedTranscriptAndUsageDoNotRebuildTaskPicker() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		var initial = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: "replay",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .running,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		initial.taskWorkspaces = [TaskWorkspaceChoice(
			id: UUID(),
			title: "Task",
			checkoutPath: "/tmp/task",
			branch: "codex/task",
			sourceWasDirty: false,
			phase: .active,
			executionState: .running,
			issue: nil,
			canRemoveCheckout: false
		)]
		initial.workspaceOwner = ConversationPresentationTestFixture
			.presentationOwner(sessionID: UUID())
		controller.render(NavigationPresentation(initial))
		let taskItem = try #require(controller.taskMenuItems.dropFirst().first)
		var streamed = ConversationSnapshot(
			projectPath: initial.projectPath,
			threads: [],
			selectedThreadID: "replay",
			entries: [ConversationEntry(
				id: "answer",
				kind: .agent,
				title: "Codex",
				body: "A streamed response"
			)],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .running,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		streamed.workspaceOwner = initial.workspaceOwner
		streamed.taskWorkspaces = initial.taskWorkspaces
		streamed.usageError = "Usage temporarily unavailable"
		controller.render(NavigationPresentation(streamed))
		#expect(controller.taskMenuItems.dropFirst().first === taskItem)
		streamed.workspaceSelectionEpoch += 1
		controller.render(NavigationPresentation(streamed))
		#expect(controller.taskMenuItems.dropFirst().first !== taskItem)
	}

	@Test func sidebarKeepsHistorySelectableAndMarksOwningTask() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let workingThread = try #require(
			ThreadSummary(json: [
				"id": "working",
				"name": "Active work",
				"cwd": "/tmp/replay",
			])
		)
		let historyThread = try #require(
			ThreadSummary(json: [
				"id": "history",
				"name": "History",
				"cwd": "/tmp/replay",
			])
		)
		var selectedThread: String?
		controller.onSelectThread =
		{
			selectedThread = $0
		}
		func makeSidebarSnapshot(selectedThreadID: String) -> ConversationSnapshot
		{
			ConversationSnapshot(
				projectPath: "/tmp/replay",
				threads: [workingThread, historyThread],
				selectedThreadID: selectedThreadID,
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Mock",
				backendDescription: "Mock",
				executionState: .running,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			)
		}
		var sidebarSnapshot = makeSidebarSnapshot(selectedThreadID: "working")
		sidebarSnapshot.activeThreadID = "working"
		sidebarSnapshot.activeExecutionState = .awaitingApproval
		controller.render(sidebarSnapshot)
		let table = try #require(findNavigationTable(in: controller.view))
		#expect(table.isEnabled)
		#expect(table.numberOfRows == 3)
		let activeCell = try #require(table.view(
			atColumn: 0,
			row: 1,
			makeIfNecessary: true
		))
		#expect(activeCell.accessibilityLabel()?.contains("Awaiting approval task") == true)
		table.selectRowIndexes(
			IndexSet(integer: 2),
			byExtendingSelection: false
		)
		#expect(selectedThread == "history")

		sidebarSnapshot.activeExecutionState = .running
		controller.render(sidebarSnapshot)
		let runningCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 1
		)
			as? TaskSidebarCellView)
		let historyCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 2
		)
			as? TaskSidebarCellView)
		#expect(runningCell.progressRing.isRunning)
		#expect(!runningCell.progressRing.isHidden)
		#expect(runningCell.textField?.stringValue == "Active work")
		#expect(!historyCell.progressRing.isRunning)
		#expect(historyCell.progressRing.isHidden)
		for state in [ExecutionState.awaitingApproval,
						.awaitingAnswer,
						.stopping,
						.completed,
						.stopped,
						.failed,
						.disconnected]
		{
			sidebarSnapshot.activeExecutionState = state
			controller.render(sidebarSnapshot)
			let cell = try #require(controller.tableView(
				table,
				viewFor: nil,
				row: 1
			)
				as? TaskSidebarCellView)
			#expect(!cell.progressRing.isRunning)
			#expect(cell.progressRing.isHidden)
		}

		sidebarSnapshot = makeSidebarSnapshot(selectedThreadID: "history")
		sidebarSnapshot.activeThreadID = "working"
		sidebarSnapshot.activeExecutionState = .completed
		sidebarSnapshot.activeExecutionState = .running
		controller.render(sidebarSnapshot)
		sidebarSnapshot.activeExecutionState = .completed
		controller.render(sidebarSnapshot)
		let unreadCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 1
		)
			as? TaskSidebarCellView)
		#expect(!unreadCell.unreadDot.isHidden)
		#expect(unreadCell.progressRing.isHidden)
		#expect(unreadCell.textField?.stringValue == "Active work")
		#expect(unreadCell.textField?.textColor == .labelColor)
		#expect(unreadCell.accessibilityLabel()?.contains("Unread result") == true)
		unreadCell.frame = NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 30
		)
		unreadCell.layoutSubtreeIfNeeded()
		#expect(unreadCell.unreadDot.frame.midX == unreadCell.progressRing.frame.midX)
		#expect(unreadCell.unreadDot.frame.width == 8)
		sidebarSnapshot = makeSidebarSnapshot(selectedThreadID: "working")
		sidebarSnapshot.activeThreadID = "working"
		sidebarSnapshot.activeExecutionState = .completed
		controller.render(sidebarSnapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		sidebarSnapshot = makeSidebarSnapshot(selectedThreadID: "history")
		sidebarSnapshot.activeThreadID = "working"
		sidebarSnapshot.activeExecutionState = .completed
		controller.render(sidebarSnapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		sidebarSnapshot.activeExecutionState = .running
		controller.render(sidebarSnapshot)
		sidebarSnapshot.activeExecutionState = .completed
		sidebarSnapshot.taskOutcomeUncertain = true
		controller.render(sidebarSnapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		sidebarSnapshot.taskOutcomeUncertain = false
		controller.render(sidebarSnapshot)
		#expect(controller.unreadThreadIDs == ["working"])

		sidebarSnapshot.activeThreadID = nil
		sidebarSnapshot.activeExecutionState = .running
		controller.render(sidebarSnapshot)
		let newChatButton = try #require(findNavigationButton(
			in: controller.view,
			title: "New Chat"
		))
		#expect(table.isEnabled)
		#expect(newChatButton.isEnabled)
	}

	private func findNavigationTable(in view: NSView) -> NSTableView?
	{
		if let table = view as? NSTableView
		{
			return table
		}
		return view.subviews.lazy.compactMap
		{
			findNavigationTable(in: $0)
		}.first
	}

	private func findNavigationButton(
		in view: NSView,
		title: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.title == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findNavigationButton(
				in: $0,
				title: title
			)
		}.first
	}

}
