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
		) as? NSTableCellView)
		let button = try #require(cell.subviews.first(where:
			{
				$0 is NSButton
			}) as? NSButton)
		#expect(cell.textField?.stringValue == "Show more")
		#expect(button.accessibilityLabel() == "Show more")
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

	// This fixture makes its window key and presents a transient hover card.
	@Test func taskArchiveButtonRoutesToItsOwnRowWithoutChangingSelection() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
			let fixture = try attachedTaskCell()
			defer
			{
				fixture.cell.mouseExited(with: fixture.event)
				fixture.cell.removeFromSuperview()
				fixture.window.close()
			}
			var archived: String?
			fixture.controller.onArchiveTask =
			{
				archived = $0
			}
			fixture.cell.mouseEntered(with: fixture.event)
			let button = fixture.cell.archiveButton
			try #require(button.isEnabled)
			// Verify this row's target-action wiring without performClick's event-polling loop.
			// That native loop can stop SwiftPM's async-main executor while tests are unfinished.
			try #require(button.sendAction(
				try #require(button.action),
				to: button.target
			))
			#expect(archived == "hovered")
			#expect(fixture.controller.selectedThreadID == "another")
		}
	}

	private func attachedTaskCell() throws -> (
		controller: NavigationViewController,
		cell: TaskSidebarCellView,
		label: HoverScrollingTextField,
		window: NSWindow,
		event: NSEvent
	)
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
		) as? TaskSidebarCellView)
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
		window.prepareForTesting()
		window.contentView?.addSubview(cell)
		window.makeKeyAndOrderFront(nil)
		cell.setTurnRunning(true)
		cell.layoutSubtreeIfNeeded()
		do
		{
			let label = try #require(cell.textField as? HoverScrollingTextField)
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
			return (controller, cell, label, window, event)
		}
		catch
		{
			cell.removeFromSuperview()
			window.close()
			throw error
		}
	}

	private func sidebarScenario(selectedThreadID: String) throws -> (
		controller: NavigationViewController,
		table: NSTableView,
		snapshot: ConversationSnapshot
	)
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		var snapshot = try sidebarSnapshot(selectedThreadID: selectedThreadID)
		snapshot.activeThreadID = "working"
		snapshot.activeExecutionState = .awaitingApproval
		controller.render(snapshot)
		let table = try #require(findNavigationTable(in: controller.view))
		return (controller, table, snapshot)
	}

	private func sidebarSnapshot(selectedThreadID: String) throws -> ConversationSnapshot
	{
		let workingThread = try #require(ThreadSummary(json: [
			"id": "working",
			"name": "Active work",
			"cwd": "/tmp/replay",
		]))
		let historyThread = try #require(ThreadSummary(json: [
			"id": "history",
			"name": "History",
			"cwd": "/tmp/replay",
		]))
		return makeSnapshot(
			threads: [workingThread, historyThread],
			selectedThreadID: selectedThreadID
		)
	}

	private func makeSnapshot(
		threads: [ThreadSummary] = [],
		selectedThreadID: String,
		entries: [ConversationEntry] = []
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: threads,
			selectedThreadID: selectedThreadID,
			entries: entries,
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
