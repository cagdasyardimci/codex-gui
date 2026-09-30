import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationViewControllerTests
{
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
