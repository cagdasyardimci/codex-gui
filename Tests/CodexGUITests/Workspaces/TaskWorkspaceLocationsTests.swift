import Foundation
import Testing

@testable import CodexGUI

@Suite("Task workspace locations")
struct TaskWorkspaceLocationsTests
{
	@Test func configuredRootKeepsBothWorkspaceStoresInTheIsolatedDirectory()
	{
		let isolatedRoot = FileManager.default.temporaryDirectory
			.appendingPathComponent("QA workspace \(UUID().uuidString)")
		let locations = TaskWorkspaceLocations(environment: [
			"CODEX_GUI_WORKSPACE_ROOT": isolatedRoot.path
		])
		let canonicalRoot = isolatedRoot.standardizedFileURL.resolvingSymlinksInPath()
		#expect(locations.records == canonicalRoot.appendingPathComponent(
			"records",
			isDirectory: true
		))
		#expect(
			locations.checkouts == canonicalRoot.appendingPathComponent(
				"checkouts",
				isDirectory: true
			)
		)
		#expect(!locations.root.path.contains("Application Support/CodexGUI"))
	}
}
