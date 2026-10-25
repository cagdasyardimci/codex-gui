import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct SidebarOrganizationTests
{

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
