import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationViewControllerTests
{
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

	@Test func taskTitleStaysStillAndHoverCardUsesMetadataForItsOwnRow() async throws
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
			cell.removeFromSuperview(); window.orderOut(nil)
		}
		cell.layoutSubtreeIfNeeded()
		let label = try #require(cell.textField)
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
		cell.mouseEntered(with: event)
		let panel = try #require(cell.hoverCard?.panel)
		#expect(panel.isVisible)
		#expect(panel.parent === window)
		#expect(panel.animationBehavior == .none)
		#expect(panel.ignoresMouseEvents)
		#expect(label.toolTip == nil)
		#expect(cell.hoverCard?.title == label.stringValue)
		#expect(cell.hoverCard?.projectName == "codex-gui")
		cell.layoutSubtreeIfNeeded()
		#expect(label.frame == restingFrame)
		var archived: String?
		controller.onArchiveTask =
		{
			archived = $0
		}
		cell.archiveButton.performClick(nil)
		#expect(archived == "hovered")
		#expect(controller.selectedThreadID == "another")
		cell.mouseExited(with: event)
		#expect(cell.hoverCard?.panel == nil)
		#expect(!panel.isVisible)
		cell.layoutSubtreeIfNeeded()
		label.stringValue = "Short"
		cell.mouseEntered(with: event)
		#expect(label.frame == restingFrame)
		#expect(cell.hoverCard?.panel != nil)
		NotificationCenter.default.post(
			name: NSWindow.didResignKeyNotification,
			object: window
		)
		#expect(cell.hoverCard?.panel == nil)
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
		var sidebarSnapshot = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [workingThread, historyThread],
			selectedThreadID: "working",
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

		sidebarSnapshot.activeThreadID = nil
		sidebarSnapshot.activeExecutionState = .running
		controller.render(sidebarSnapshot)
		let newChatButton = try #require(findNavigationButton(
			in: controller.view,
			title: "New Chat"
		))
		#expect(!table.isEnabled)
		#expect(!newChatButton.isEnabled)
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
