import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct SidebarOrganizationTests
{
	@Test func menuSelectionsPersistAndReorderWithoutChangingSelection() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "SidebarOrganization")
		defer
		{
			fixture.cleanup()
		}
		let controller = NavigationViewController()
		controller.sidebarPreferences = SidebarPreferences(defaults: fixture.defaults)
		_ = controller.view
		controller.currentProject = URL(fileURLWithPath: "/tmp/sidebar-organization")
		controller.threads = try [task(
			"old",
			updatedAt: 1
		), task(
			"new",
			updatedAt: 2
		)]
		controller.selectedThreadID = "old"
		controller.filterThreads()
		controller.setSidebarOrganization(.oneList)
		controller.setSidebarSortOrder(.manual)
		#expect(threadIDs(controller.sidebarItems) == ["new", "old"])
		#expect(controller.moveSidebarThread(
			"old",
			toRow: 0
		))
		#expect(threadIDs(controller.sidebarItems) == ["old", "new"])
		#expect(controller.selectedThreadID == "old")
		#expect(controller.chatsTable.selectedRow == 0)
		let restored = SidebarPreferences(defaults: fixture.defaults)
		#expect(restored.organization == .oneList)
		#expect(restored.sortOrder == .manual)
		#expect(restored.manualThreadIDs == ["old", "new"])
		controller.searchField.stringValue = "old"
		controller.filterThreads()
		#expect(!controller.moveSidebarThread(
			"old",
			toRow: 0
		))
		controller.searchField.stringValue = ""
		controller.setSidebarSortOrder(.lastUpdated)
		#expect(threadIDs(controller.sidebarItems) == ["new", "old"])
	}

	@Test func flatPresentationMergesProjectsAndKeepsCurrentSummariesAuthoritative() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "SidebarGlobalPresentation")
		defer
		{
			fixture.cleanup()
		}
		let controller = NavigationViewController()
		controller.sidebarPreferences = SidebarPreferences(defaults: fixture.defaults)
		controller.sidebarPreferences.organization = .oneList
		let local = try task(
			"local",
			updatedAt: 2
		)
		let foreign = try #require(ThreadSummary(json: [
			"id": "foreign",
			"cwd": "/tmp/other",
			"updatedAt": 1.0,
		]))
		var stale = local
		stale.name = "Outdated title"
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/sidebar-organization",
			threads: [local],
			selectedThreadID: local.id,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: true,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.sidebarThreads = [stale, foreign]
		controller.render(snapshot)
		#expect(threadIDs(controller.sidebarItems) == ["local", "foreign"])
		#expect(controller.visibleThreads.first?.name == local.name)
		#expect((controller.projectsHeader?.arrangedSubviews.first as? NSTextField)?
			.stringValue == "Recents")
		var selected: ThreadSummary?
		controller.onSelectSidebarTask =
		{
			selected = $0
		}
		controller.chatsTable.selectRowIndexes(
			IndexSet(integer: 1),
			byExtendingSelection: false
		)
		#expect(selected?.id == foreign.id)
		#expect(selected?.cwd == foreign.cwd)
		var refreshes = 0
		controller.onLoadSidebarThreads =
		{
			refreshes += 1
		}
		controller.refresh()
		#expect(refreshes == 1)
	}

	@Test func flatListKeepsPinsSeparateAndGroupedModeLimitsChats() throws
	{
		let project = URL(fileURLWithPath: "/tmp/sidebar-organization")
		let tasks = try (0 ..< 7).map
		{
			try task(
				"\($0)",
				updatedAt: $0
			)
		}
		let flat = NavigationSidebarItemsBuilder.build(
			recentProjects: [project],
			currentProject: project,
			pinnedProjectPaths: [],
			visibleThreads: tasks,
			pinnedTasks: [tasks[0]],
			isCurrentProjectCollapsed: true,
			organization: .oneList
		)
		#expect(threadIDs(flat) == ["6", "5", "4", "3", "2", "1"])
		#expect(flat.contains
		{
			if case .pinnedThread = $0
			{
				return true
			}; return false
		})
		#expect(!flat.contains
		{
			if case .project = $0
			{
				return true
			}; return false
		})
		let grouped = NavigationSidebarItemsBuilder.build(
			recentProjects: [project],
			currentProject: project,
			pinnedProjectPaths: [],
			visibleThreads: tasks,
			sortOrder: .manual,
			manualThreadIDs: ["2", "0", "1"]
		)
		#expect(threadIDs(grouped) == ["2", "0", "1", "6", "5"])
		#expect(grouped.contains
		{
			if case .showMore = $0
			{
				return true
			}; return false
		})
	}

	@Test func movingTruncatedChatsRetainsOtherProjectOrder() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "SidebarManualOrder")
		defer
		{
			fixture.cleanup()
		}
		let controller = NavigationViewController()
		controller.sidebarPreferences = SidebarPreferences(defaults: fixture.defaults)
		controller.sidebarPreferences.sortOrder = .manual
		controller.sidebarPreferences.manualThreadIDs = ["elsewhere", "0", "1", "2", "3"]
		_ = controller.view
		controller.currentProject = URL(fileURLWithPath: "/tmp/sidebar-organization")
		controller.projectTaskLimit = 2
		controller.threads = try (0 ..< 4).map
		{
			try task(
				"\($0)",
				updatedAt: $0
			)
		}
		controller.filterThreads()
		#expect(threadIDs(controller.sidebarItems) == ["0", "1"])
		#expect(controller.moveSidebarThread(
			"0",
			toRow: 3
		))
		#expect(controller.sidebarPreferences.manualThreadIDs == ["elsewhere", "1", "0", "2", "3"])
		#expect(!controller.moveSidebarThread(
			"elsewhere",
			toRow: 1
		))
		#expect(!controller.moveSidebarThread(
			"1",
			toRow: 0
		))
	}

	private func threadIDs(_ items: [NavigationSidebarItem]) -> [String]
	{
		items.compactMap
		{
			if case .thread(let thread) = $0
			{
				return thread.id
			}; return nil
		}
	}

	private func task(
		_ id: String,
		updatedAt: Int
	) throws -> ThreadSummary
	{
		try #require(ThreadSummary(json: [
			"id": id,
			"name": id,
			"cwd": "/tmp/sidebar-organization",
			"updatedAt": Double(updatedAt),
		]))
	}
}
