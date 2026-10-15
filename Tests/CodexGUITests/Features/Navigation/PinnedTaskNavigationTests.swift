import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct PinnedTaskNavigationTests
{
	@Test func pinnedTasksFromDifferentProjectsPrecedeProjectsWithoutDuplicates() throws
	{
		let first = try task(
			"first",
			project: "/tmp/first"
		)
		let second = try task(
			"second",
			project: "/tmp/second"
		)
		let ordinary = try task(
			"ordinary",
			project: "/tmp/first"
		)
		let rows = NavigationSidebarItemsBuilder.build(
			recentProjects: [],
			currentProject: URL(fileURLWithPath: "/tmp/first"),
			pinnedProjectPaths: [],
			visibleThreads: [first, ordinary],
			pinnedTasks: [first, second]
		)
		#expect(rows.count == 6)
		guard case .sectionHeader("Pinned") = rows[0],
				case .pinnedThread(let firstPin) = rows[1],
				case .pinnedThread(let secondPin) = rows[2],
				case .sectionHeader("Projects") = rows[3],
				case .project = rows[4],
				case .thread(let projectTask) = rows[5]
		else
		{
			Issue.record("Pinned and project sections were not in the required order")
			return
		}
		#expect(firstPin.id == "first")
		#expect(secondPin.id == "second")
		#expect(projectTask.id == "ordinary")
	}

	@Test func pinnedSelectionCarriesProjectAndTaskAndHeadersCannotBeSelected() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let pin = try task(
			"other",
			project: "/tmp/other"
		)
		controller.currentProject = URL(fileURLWithPath: "/tmp/current")
		controller.pinnedTasks = [pin]
		controller.filterThreads()
		var selection: ThreadSummary?
		controller.onSelectPinnedTask =
		{
			selection = $0
		}
		#expect(!controller.tableView(
			controller.chatsTable,
			shouldSelectRow: 0
		))
		#expect(!controller.tableView(
			controller.chatsTable,
			shouldSelectRow: 2
		))
		controller.chatsTable.selectRowIndexes(
			IndexSet(integer: 1),
			byExtendingSelection: false
		)
		#expect(selection?.id == "other")
		#expect(selection?.cwd == "/tmp/other")
		#expect(controller.projectsHeader?.isHidden == true)
	}

	@Test func manualUnreadAppliesToTargetedTaskAndClearsWhenOpened() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		controller.currentProject = URL(fileURLWithPath: "/tmp/current")
		controller.threads = [try task(
			"first",
			project: "/tmp/current"
		),
		try task(
			"second",
			project: "/tmp/current"
		)]
		controller.selectedThreadID = "first"
		controller.filterThreads()
		controller.markTaskUnread("second")
		#expect(controller.unreadThreadIDs == ["second"])
		let cell = try #require(controller.tableView(
			controller.chatsTable,
			viewFor: nil,
			row: 2
		) as? TaskSidebarCellView)
		#expect(!cell.unreadDot.isHidden)
		controller.chatsTable.selectRowIndexes(
			IndexSet(integer: 2),
			byExtendingSelection: false
		)
		#expect(controller.unreadThreadIDs.isEmpty)
		#expect(controller.manuallyUnreadThreadIDs.isEmpty)
	}

	@Test func searchIncludesPinnedTasksFromOtherProjects() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		controller.currentProject = URL(fileURLWithPath: "/tmp/current")
		controller.pinnedTasks = [try task(
			"needle",
			project: "/tmp/other"
		)]
		controller.searchField.stringValue = "needle"
		controller.filterThreads()
		#expect(controller.emptyLabel.isHidden)
		#expect(controller.sidebarItems.contains
		{
			if case .pinnedThread(let task) = $0
			{
				return task.id == "needle"
			}
			return false
		})
	}

	private func task(
		_ id: String,
		project: String
	) throws -> ThreadSummary
	{
		try #require(ThreadSummary(json: ["id": id, "name": id, "cwd": project]))
	}
}
