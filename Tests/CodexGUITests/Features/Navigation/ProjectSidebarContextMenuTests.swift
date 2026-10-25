import AppKit
import Testing
@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
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
