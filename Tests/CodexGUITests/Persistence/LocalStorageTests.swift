import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Local storage"
)
struct LocalStorageTests
{
	@Test("Remote access choice persists across storage instances")
	@MainActor
	func remoteAccessChoicePersists() throws
	{
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "LocalStorageTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let first = LocalStorage(defaults: defaultsFixture.defaults)
		#expect(!first.remoteAccessEnabled)
		first.saveRemoteAccessEnabled(true)
		#expect(LocalStorage(defaults: defaultsFixture.defaults).remoteAccessEnabled)
		let restored = WorkspaceStoreFactory.makeSource(
			dependencies: WorkspaceStoreDependencies(
				service: MockCodexService(),
				storage: LocalStorage(defaults: defaultsFixture.defaults)
			)
		)
		#expect(restored.model.remoteAccess.desiredEnabled)
		restored.shutdown()
		first.saveRemoteAccessEnabled(false)
		#expect(!LocalStorage(defaults: defaultsFixture.defaults).remoteAccessEnabled)
	}

	@Test("Recent projects are unique, newest first, and limited to ten")
	@MainActor
	func recentProjectsAreUniqueNewestFirstAndLimited() throws
	{
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "LocalStorageTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let storage = LocalStorage(defaults: defaultsFixture.defaults)
		let rootURL = temporaryRootURL()

		for projectIndex in 0 ..< 12
		{
			let projectURL = rootURL.appendingPathComponent("project-\(projectIndex)")
			storage.rememberProject(projectURL)
		}

		let newestProjectURL = rootURL.appendingPathComponent("project-11")
		storage.rememberProject(newestProjectURL)

		#expect(storage.recentProjects.count == 10)
		#expect(storage.recentProjects.first?.path == newestProjectURL.path)
		#expect(
			storage.recentProjects.last?.path == rootURL.appendingPathComponent("project-2").path
		)
		#expect(Set(storage.recentProjects.map(\.path)).count == 10)
	}

	@Test("Legacy recent project and draft values are migrated")
	@MainActor
	func legacyRecentProjectAndDraftAreMigrated() throws
	{
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "LocalStorageTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let defaults = defaultsFixture.defaults
		let legacyProjectURL = temporaryRootURL().appendingPathComponent("legacy-project")
		defaults.set(
			legacyProjectURL.path,
			forKey: "recentProject"
		)
		defaults.set(
			"legacy draft",
			forKey: "draft"
		)

		let storage = LocalStorage(defaults: defaults)

		#expect(storage.recentProjects.first?.path == legacyProjectURL.path)
		#expect(storage.draft(
			for: legacyProjectURL,
			threadID: nil
		) == "legacy draft")
		#expect(defaults.object(forKey: "recentProject") == nil)
		#expect(defaults.object(forKey: "draft") == nil)
	}

}

private func temporaryRootURL() -> URL
{
	FileManager.default.temporaryDirectory
		.appendingPathComponent(
			"LocalStorageTests-\(UUID().uuidString)",
			isDirectory: true
		)
}
