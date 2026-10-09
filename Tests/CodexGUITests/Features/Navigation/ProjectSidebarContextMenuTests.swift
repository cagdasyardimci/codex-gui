import AppKit
import Testing
@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ProjectSidebarContextMenuTests
{
	@Test func projectMenuOrderAndCapturedActions() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		_ = controller.view
		let project = URL(fileURLWithPath: "/tmp/project-menu").standardizedFileURL
			.resolvingSymlinksInPath()
		controller.currentProject = project
		controller.canManageSidebarTasks = true
		controller.filterThreads()
		var actions: [String] = []
		controller.onToggleProjectPin =
		{
			actions.append("pin:" + $0.path)
		}
		controller.onRenameProject =
		{
			_, _ in
		}
		controller.onArchiveProjectChats =
		{
			actions.append("archive:" + $0.path)
		}
		controller.onRemoveProject =
		{
			actions.append("remove:" + $0.path)
		}
		let menu = try #require(controller.taskContextMenu(for: 0))
		#expect(menu.items.map(\.title) == ["Pin",
											"Rename",
											"",
											"Reveal in Finder",
											"",
											"Archive chats",
											"",
											"Remove project"])
		#expect(menu.items.filter
		{
			!$0.isSeparatorItem
		}
		.allSatisfy
		{
			$0.image?.isTemplate == true
		})
		controller.onToggleProjectPin =
		{
			_ in actions.append("wrong")
		}
		controller.onRemoveProject = nil
		for index in [0, 5, 7]
		{
			menu.performActionForItem(at: index)
		}
		#expect(actions == [
			"pin:" + project.path,
			"archive:" + project.path,
			"remove:" + project.path
		])
		controller.pinnedProjectPaths = [project.path]
		#expect(controller.projectContextMenu(project).items[0].title == "Unpin")
		controller.canManageSidebarTasks = false
		#expect(!controller.projectContextMenu(project).items[5].isEnabled)
	}

	@Test func pinnedProjectsShareSectionWithTasksAndKeepChildren() throws
	{
		let project = URL(fileURLWithPath: "/tmp/pinned-project").standardizedFileURL
			.resolvingSymlinksInPath()
		let other = URL(fileURLWithPath: "/tmp/other-project").standardizedFileURL
			.resolvingSymlinksInPath()
		let task = try #require(ThreadSummary(json: ["id": "task", "cwd": project.path]))
		let pin = try #require(ThreadSummary(json: ["id": "pin", "cwd": other.path]))
		let rows = NavigationSidebarItemsBuilder.build(
			recentProjects: [other, project],
			currentProject: project,
			pinnedProjectPaths: [project.path],
			visibleThreads: [
				task,
				pin
			],
			pinnedTasks: [pin]
		)
		#expect(rows.count == 6)
		guard case .sectionHeader("Pinned") = rows[0], case .pinnedThread = rows[1],
				case .project(let pinnedProject) = rows[2], case .thread(let child) = rows[3],
				case .sectionHeader("Projects") = rows[4],
				case .project(let ordinaryProject) = rows[5]
		else
		{
			Issue.record("Incorrect pinned project placement"); return
		}
		#expect(pinnedProject == project)
		#expect(child.id == task.id)
		#expect(ordinaryProject == other)
		let hidden = NavigationSidebarItemsBuilder.build(
			recentProjects: [project],
			currentProject: project,
			pinnedProjectPaths: [project.path],
			visibleThreads: [task],
			removedProjectPaths: [project.path]
		)
		#expect(hidden.isEmpty)
		let projectOnly = NavigationSidebarItemsBuilder.build(
			recentProjects: [],
			currentProject: project,
			pinnedProjectPaths: [project.path],
			visibleThreads: [task]
		)
		guard case .sectionHeader("Pinned") = projectOnly.first
		else
		{
			Issue.record("Pinned projects alone need a Pinned header"); return
		}
	}

	@Test func removingAndReopeningProjectPreservesDraftsAndPersistsVisibility() throws
	{
		let fixture = try IsolatedUserDefaultsFixture(prefix: "ProjectRemovalTests")
		defer
		{
			fixture.cleanup()
		}
		let storage = LocalStorage(defaults: fixture.defaults)
		let project = URL(fileURLWithPath: "/tmp/project-removal").standardizedFileURL
			.resolvingSymlinksInPath()
		storage.rememberProject(project)
		storage.toggleProjectPin(project)
		storage.saveDraft(
			"Keep this draft",
			for: project,
			threadID: nil
		)
		storage.removeProject(project)
		let restored = LocalStorage(defaults: fixture.defaults)
		#expect(restored.removedProjectPaths == [project.path])
		#expect(restored.pinnedProjectPaths.isEmpty)
		#expect(restored.recentProjects.isEmpty)
		#expect(restored.draft(
			for: project,
			threadID: nil
		) == "Keep this draft")
		restored.rememberProject(project)
		#expect(restored.removedProjectPaths.isEmpty)
		#expect(restored.recentProjects == [project])
	}
}
