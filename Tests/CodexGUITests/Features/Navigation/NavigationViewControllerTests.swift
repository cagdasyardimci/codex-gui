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

	@Test func taskTitleScrollsOnceAndResetsAfterHover() throws
	{
		let fixture = try attachedTaskCell()
		defer
		{
			fixture.cell.mouseExited(with: fixture.event)
			fixture.cell.removeFromSuperview()
			fixture.window.close()
		}
		let cell = fixture.cell
		let label = fixture.label
		let restingFrame = label.frame
		#expect(cell.progressRing.frame.maxX == cell.bounds.maxX - 4)
		#expect(cell.progressRing.alphaValue == 1)
		#expect(label.alignmentRect(forFrame: restingFrame).minX == 26)
		#expect(label.lineBreakMode == .byTruncatingTail)
		#expect(label.cell?.isScrollable == false)
		#expect(!label.allowsExpansionToolTips)

		cell.setTurnRunning(false)
		cell.setUnread(true)
		cell.mouseEntered(with: fixture.event)
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
		cell.layoutSubtreeIfNeeded()
		#expect(label.frame == hoveredFrame)
		cell.mouseExited(with: fixture.event)
		#expect(label.scrollOffset == 0)
		#expect(cell.progressRing.alphaValue == 1)
		#expect(cell.unreadDot.alphaValue == 1)
		#expect(cell.archiveButton.superview?.alphaValue == 0)
		cell.layoutSubtreeIfNeeded()
		#expect(label.frame == restingFrame)
		label.stringValue = "Short"
		cell.mouseEntered(with: fixture.event)
		label.advanceScrolling(elapsed: 1.6)
		#expect(label.scrollOffset == 0)
		#expect(label.frame == hoveredFrame)
		#expect(cell.hoverCard?.panel != nil)
	}

	@Test func taskHoverCardUsesOwnRowMetadataAndDismissesOnExitOrWindowResign() throws
	{
		let fixture = try attachedTaskCell()
		defer
		{
			fixture.cell.mouseExited(with: fixture.event)
			fixture.cell.removeFromSuperview()
			fixture.window.close()
		}
		let cell = fixture.cell
		let label = fixture.label
		var previousHeight: CGFloat = 0
		for title in [
			"Short",
			"Clarify project-wide change summary scope",
			"Explain why the change summary appears during an ongoing agent turn",
		]
		{
			let card = TaskHoverCard(
				title: title,
				projectName: "codex-gui",
				updatedAt: Date().addingTimeInterval(-660)
			)
			card.show(beside: cell)
			defer
			{
				card.dismiss()
			}
			let hoverPanel = try #require(card.panel)
			let surface = try #require(hoverPanel.contentView)
			surface.layoutSubtreeIfNeeded()
			let stack = try #require(surface.subviews.first as? NSStackView)
			let header = try #require(stack.arrangedSubviews.first as? NSStackView)
			let titleLabel = try #require(header.arrangedSubviews.first as? NSTextField)
			let metadata = try #require(header.arrangedSubviews.last as? NSStackView)
			let timeLabel = try #require(metadata.arrangedSubviews.last as? NSTextField)
			#expect(hoverPanel.frame.width == 320)
			#expect(surface.frame.width == 320)
			#expect(hoverPanel.frame.height > previousHeight)
			#expect(!surface.hasAmbiguousLayout)
			#expect(titleLabel.frame.maxX <= metadata.frame.minX)
			#expect(abs(titleLabel.frame.maxY - metadata.frame.maxY) < 1)
			#expect(timeLabel.frame.width >= timeLabel.intrinsicContentSize.width)
			let textHeight = (title as NSString).boundingRect(
				with: NSSize(
					width: titleLabel.bounds.width,
					height: .greatestFiniteMagnitude
				),
				options: [.usesLineFragmentOrigin, .usesFontLeading],
				attributes: [.font: try #require(titleLabel.font)]
			).height
			#expect(titleLabel.bounds.height >= ceil(textHeight))
			previousHeight = hoverPanel.frame.height
		}
		cell.mouseEntered(with: fixture.event)
		let panel = try #require(cell.hoverCard?.panel)
		#expect(panel.isVisible)
		#expect(panel.parent === fixture.window)
		#expect(panel.animationBehavior == .none)
		#expect(panel.ignoresMouseEvents)
		#expect(label.toolTip == nil)
		#expect(cell.hoverCard?.title == label.stringValue)
		#expect(cell.hoverCard?.projectName == "codex-gui")
		cell.mouseExited(with: fixture.event)
		#expect(cell.hoverCard?.panel == nil)
		#expect(!panel.isVisible)
		cell.mouseEntered(with: fixture.event)
		#expect(cell.hoverCard?.panel != nil)
		NotificationCenter.default.post(
			name: NSWindow.didResignKeyNotification,
			object: fixture.window
		)
		#expect(cell.hoverCard?.panel == nil)
		#expect(cell.progressRing.alphaValue == 1)
	}

	@Test func taskArchiveButtonRoutesToItsOwnRowWithoutChangingSelection() throws
	{
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
		fixture.cell.archiveButton.performClick(nil)
		#expect(archived == "hovered")
		#expect(fixture.controller.selectedThreadID == "another")
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
		window.isReleasedWhenClosed = false
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

	@Test func streamedTranscriptAndUsageDoNotRebuildTaskPicker() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		var initial = makeSnapshot(selectedThreadID: "replay")
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
		var streamed = makeSnapshot(
			selectedThreadID: "replay",
			entries: [ConversationEntry(
				id: "answer",
				kind: .agent,
				title: "Codex",
				body: "A streamed response"
			)]
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
		let scenario = try sidebarScenario(selectedThreadID: "working")
		let controller = scenario.controller
		let table = scenario.table
		var selectedThread: String?
		controller.onSelectThread =
		{
			selectedThread = $0
		}
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
	}

	@Test func sidebarProgressRingOnlyFollowsOwningRunningTask() throws
	{
		let scenario = try sidebarScenario(selectedThreadID: "working")
		let controller = scenario.controller
		let table = scenario.table
		var snapshot = scenario.snapshot
		snapshot.activeExecutionState = .running
		controller.render(snapshot)
		let runningCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 1
		) as? TaskSidebarCellView)
		let historyCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 2
		) as? TaskSidebarCellView)
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
			snapshot.activeExecutionState = state
			controller.render(snapshot)
			let cell = try #require(controller.tableView(
				table,
				viewFor: nil,
				row: 1
			) as? TaskSidebarCellView)
			#expect(!cell.progressRing.isRunning)
			#expect(cell.progressRing.isHidden)
		}
	}

	@Test func sidebarUnreadResultTracksCompletionAndUncertainOutcome() throws
	{
		let scenario = try sidebarScenario(selectedThreadID: "history")
		let controller = scenario.controller
		let table = scenario.table
		var snapshot = scenario.snapshot
		snapshot.activeExecutionState = .running
		controller.render(snapshot)
		snapshot.activeExecutionState = .completed
		controller.render(snapshot)
		let unreadCell = try #require(controller.tableView(
			table,
			viewFor: nil,
			row: 1
		) as? TaskSidebarCellView)
		#expect(!unreadCell.unreadDot.isHidden)
		#expect(unreadCell.progressRing.isHidden)
		#expect(unreadCell.textField?.stringValue == "Active work")
		#expect(unreadCell.textField?.textColor == AppKitColorTokens.sidebarText)
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

		snapshot = try sidebarSnapshot(selectedThreadID: "working")
		snapshot.activeThreadID = "working"
		snapshot.activeExecutionState = .completed
		controller.render(snapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		snapshot = try sidebarSnapshot(selectedThreadID: "history")
		snapshot.activeThreadID = "working"
		snapshot.activeExecutionState = .completed
		controller.render(snapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		snapshot.activeExecutionState = .running
		controller.render(snapshot)
		snapshot.activeExecutionState = .completed
		snapshot.taskOutcomeUncertain = true
		controller.render(snapshot)
		#expect(controller.unreadThreadIDs.isEmpty)
		snapshot.taskOutcomeUncertain = false
		controller.render(snapshot)
		#expect(controller.unreadThreadIDs == ["working"])
	}

	@Test func sidebarAllowsNewChatWhileAnonymousWorkRuns() throws
	{
		let scenario = try sidebarScenario(selectedThreadID: "history")
		let controller = scenario.controller
		let table = scenario.table
		var snapshot = scenario.snapshot
		snapshot.activeThreadID = nil
		snapshot.activeExecutionState = .running
		controller.render(snapshot)
		let newChatButton = try #require(findNavigationButton(
			in: controller.view,
			title: "New Chat"
		))
		#expect(table.isEnabled)
		#expect(newChatButton.isEnabled)
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
