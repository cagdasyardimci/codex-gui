import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct NavigationMenuRenderingTests
{
	@Test func statusAndSelectionUpdatesKeepMenuItemsAndRefreshControls() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let project = URL(fileURLWithPath: "/fixture/project")
		let workspace = makeWorkspace()
		var initial = makeSnapshot(recentProjects: [project])
		initial.taskWorkspaces = [workspace]
		initial.projectDisplayNames = [project.path: "Örnek 📁"]
		controller.render(initial)
		let taskItem = try #require(controller.taskPicker.item(at: 1))
		let taskActions = try #require(controller.taskPicker.itemArray.last?.submenu)
		let removalItem = try #require(taskActions.items.first)
		let recentItem = try #require(controller.recentProjectsButton.item(at: 1))

		var updated = makeSnapshot(
			selectedThreadID: "other",
			recentProjects: [project]
		)
		updated.taskWorkspaces = initial.taskWorkspaces
		updated.projectDisplayNames = initial.projectDisplayNames
		updated.selectedTaskWorkspaceID = workspace.id
		updated.activeThreadID = "active"
		updated.activeExecutionState = .awaitingApproval
		updated.taskStatusSummary = "1 running task"
		updated.taskWorkspaceMessage = "Yanıt gerekiyor · λ"
		controller.render(updated)
		#expect(controller.taskPicker.item(at: 1) === taskItem)
		#expect(controller.taskPicker.itemArray.last?.submenu === taskActions)
		#expect(taskActions.items.first === removalItem)
		#expect(controller.recentProjectsButton.item(at: 1) === recentItem)
		#expect((controller.taskPicker.selectedItem?.representedObject as? UUID) == workspace.id)
		#expect(controller.selectedThreadID == "other")
		#expect(controller.taskSummaryLabel.stringValue == "1 running task · Yanıt gerekiyor · λ")
		#expect(controller.taskSummaryLabel.toolTip == controller.taskSummaryLabel.stringValue)
		#expect(!controller.taskSummaryLabel.isHidden)
		#expect(controller.activeTaskLabel.stringValue == "Task: Awaiting approval")
		#expect(recentItem.title == "Örnek 📁")
	}

	@Test func workspaceStateChangesRebuildAvailabilityAndKeepRecentMenu() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let project = URL(fileURLWithPath: "/fixture/project")
		let workspace = makeWorkspace()
		var snapshot = makeSnapshot(recentProjects: [project])
		snapshot.taskWorkspaces = [workspace]
		controller.render(snapshot)
		let oldTaskItem = try #require(controller.taskPicker.item(at: 1))
		let recentItem = try #require(controller.recentProjectsButton.item(at: 1))
		let oldRemoval = try #require(controller.taskPicker.itemArray.last?.submenu?.items.first)
		#expect(!oldRemoval.isEnabled)

		snapshot.taskWorkspaces = [makeWorkspace(
			id: workspace.id,
			executionState: .completed,
			canRemoveCheckout: true
		)]
		controller.render(snapshot)
		let taskItem = try #require(controller.taskPicker.item(at: 1))
		let removal = try #require(controller.taskPicker.itemArray.last?.submenu?.items.first)
		#expect(taskItem !== oldTaskItem)
		#expect(taskItem.title == "Görev λ")
		#expect(taskItem.toolTip == "/fixture/task\ncodex/menu")
		#expect(removal.isEnabled)
		#expect((removal.representedObject as? UUID) == workspace.id)
		#expect(controller.recentProjectsButton.item(at: 1) === recentItem)
	}

	@Test func renamedProjectUpdatesRecentMenuWithoutRebuildingTaskMenu() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let project = URL(fileURLWithPath: "/fixture/project")
		var snapshot = makeSnapshot(recentProjects: [project])
		snapshot.taskWorkspaces = [makeWorkspace()]
		controller.render(snapshot)
		let taskItem = try #require(controller.taskPicker.item(at: 1))
		let oldRecentItem = try #require(controller.recentProjectsButton.item(at: 1))
		snapshot.projectDisplayNames = [project.path: "Proje İstanbul"]
		controller.render(snapshot)
		let recentItem = try #require(controller.recentProjectsButton.item(at: 1))
		#expect(recentItem !== oldRecentItem)
		#expect(recentItem.title == "Proje İstanbul")
		#expect((recentItem.representedObject as? URL) == project)
		#expect(recentItem.toolTip == project.path)
		#expect(controller.taskPicker.item(at: 1) === taskItem)
	}

	@Test(arguments: ["title", "checkoutPath", "branch", "issue"])
	func canonicalWorkspaceTextChangesRefreshLiteralMenuContent(field: String) throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let originalText = "Café"
		let changedText = "Cafe\u{0301}"
		let workspace = makeWorkspace(
			title: originalText,
			checkoutPath: "/fixture/" + originalText,
			branch: "codex/" + originalText,
			issue: originalText
		)
		var snapshot = makeSnapshot()
		snapshot.taskWorkspaces = [workspace]
		controller.render(snapshot)
		let oldTaskItem = try #require(controller.taskPicker.item(at: 1))
		let changed = makeWorkspace(
			id: workspace.id,
			title: field == "title" ? changedText : originalText,
			checkoutPath: "/fixture/" + (field == "checkoutPath" ? changedText : originalText),
			branch: "codex/" + (field == "branch" ? changedText : originalText),
			issue: field == "issue" ? changedText : originalText
		)
		#expect(workspace == changed)
		snapshot.taskWorkspaces = [changed]
		snapshot.taskStatusSummary = "Current task status"
		controller.render(snapshot)
		let taskItem = try #require(controller.taskPicker.item(at: 1))
		#expect(taskItem !== oldTaskItem)
		let expectedTitle =
			"● \(ExecutionState.running.title) · \(changed.title) · \(changed.issue ?? "")"
		#expect(taskItem.title.utf8.elementsEqual(expectedTitle.utf8))
		#expect(taskItem.toolTip?.utf8.elementsEqual(
			"\(changed.checkoutPath)\n\(changed.branch)".utf8
		) == true)
	}

	@Test func canonicalProjectNameChangesRefreshLiteralMenuContentWithoutRebuildingTasks() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let project = URL(fileURLWithPath: "/fixture/project")
		var snapshot = makeSnapshot(recentProjects: [project])
		snapshot.taskWorkspaces = [makeWorkspace()]
		snapshot.projectDisplayNames = [project.path: "Café"]
		controller.render(snapshot)
		let taskItem = try #require(controller.taskPicker.item(at: 1))
		let oldRecentItem = try #require(controller.recentProjectsButton.item(at: 1))
		snapshot.projectDisplayNames = [project.path: "Cafe\u{0301}"]
		snapshot.taskStatusSummary = "Current task status"
		controller.render(snapshot)
		let recentItem = try #require(controller.recentProjectsButton.item(at: 1))
		#expect(recentItem !== oldRecentItem)
		#expect(recentItem.title.utf8.elementsEqual("Cafe\u{0301}".utf8))
		#expect(controller.taskPicker.item(at: 1) === taskItem)
	}

	@Test func recentProjectAvailabilityEnablesTaskCreationWithoutOwnerChange() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let initial = makeSnapshot(projectPath: nil)
		controller.render(initial)
		let oldCreate = try #require(controller.taskMenuItems.last)
		#expect(oldCreate.title == "New Task Checkout…")
		#expect(!oldCreate.isEnabled)
		let updated = makeSnapshot(
			projectPath: nil,
			recentProjects: [URL(fileURLWithPath: "/fixture/recent")]
		)
		controller.render(updated)
		let create = try #require(controller.taskMenuItems.last)
		#expect(create !== oldCreate)
		#expect(create.title == "New Task Checkout…")
		#expect(create.isEnabled)
	}

	private func makeWorkspace(
		id: UUID = UUID(),
		title: String = "Görev λ",
		checkoutPath: String = "/fixture/task",
		branch: String = "codex/menu",
		executionState: ExecutionState = .running,
		canRemoveCheckout: Bool = false,
		issue: String? = nil
	) -> TaskWorkspaceChoice
	{
		TaskWorkspaceChoice(
			id: id,
			title: title,
			checkoutPath: checkoutPath,
			branch: branch,
			sourceWasDirty: false,
			phase: .active,
			executionState: executionState,
			issue: issue,
			canRemoveCheckout: canRemoveCheckout
		)
	}

	private func makeSnapshot(
		projectPath: String? = "/fixture/project",
		selectedThreadID: String = "selected",
		recentProjects: [URL] = []
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: projectPath,
			threads: [],
			selectedThreadID: selectedThreadID,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: recentProjects
		)
	}
}
