import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(
	.serialized
)
@MainActor
struct ConcurrentChatNavigationTests
{

	@Test func anonymousSubmissionKeepsOtherChatsAndNewChatAvailable()
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let snapshot = makeSnapshot()
		controller.render(snapshot)
		#expect(controller.chatsTable.isEnabled)
		#expect(controller.newChatButton.isEnabled)
		#expect(controller.canStartProjectChat)
	}

	@Test(arguments: [SidebarPreferences.Organization.byProject, .oneList])
	func firstMessageAppearsUnderItsProjectBeforeBackendCreation(_ organization: SidebarPreferences
		.Organization) throws
	{
		let defaults = try IsolatedUserDefaultsFixture(prefix: "PendingChatNavigation")
		defer
		{
			defaults.cleanup()
		}
		let controller = NavigationViewController()
		controller.sidebarPreferences = SidebarPreferences(defaults: defaults.defaults)
		controller.sidebarPreferences.organization = organization
		var snapshot = makeSnapshot()
		let pending = PendingChatPresentation(
			requestID: UUID(),
			projectPath: "/tmp/concurrent",
			title: "Build a feature",
			isSelected: true
		)
		controller.render(snapshot)
		controller.isCurrentProjectCollapsed = true
		snapshot.pendingChats = [pending]
		controller.render(snapshot)
		let row = try #require(controller.sidebarItems.firstIndex
		{
			if case .pendingChat(let chat) = $0
			{
				return chat == pending
			}
			return false
		})
		if organization == .byProject
		{
			guard case .project(let project) = controller.sidebarItems[row - 1]
			else
			{
				Issue.record("Expected the chat directly under its project.")
				return
			}
			#expect(project.path == pending.projectPath)
		}
		let cell = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: controller.chatsTable.tableColumns.first,
			row: row
		) as? TaskSidebarCellView)
		#expect(cell.textField?.stringValue == pending.title)
		#expect(controller.taskContextMenu(for: row) == nil)
		let hover = try #require(NSEvent.enterExitEvent(
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
		cell.mouseEntered(with: hover)
		#expect(cell.pinButton.isHiddenOrHasHiddenAncestor)
		#expect(cell.archiveButton.isHiddenOrHasHiddenAncestor)
		#expect(cell.menu(for: hover) == nil)
		cell.mouseExited(with: hover)
		#expect(controller.chatsTable.selectedRow == row)
		#expect(controller.newChatButton.isEnabled)

		let created = try #require(ThreadSummary(json: [
			"id": "created",
			"cwd": pending.projectPath,
			"preview": pending.title
		]))
		snapshot = makeSnapshot(
			threads: [created],
			selectedThreadID: created.id
		)
		controller.render(snapshot)
		#expect(!controller.sidebarItems.contains
		{
			if case .pendingChat = $0
			{
				return true
			}; return false
		})
		#expect(controller.sidebarItems.contains
		{
			if case .thread(let thread) = $0
			{
				return thread.id == created.id
			}; return false
		})
	}

	private func makeSnapshot(
		threads: [ThreadSummary] = [],
		selectedThreadID: String? = nil
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/concurrent",
			threads: threads,
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
}
