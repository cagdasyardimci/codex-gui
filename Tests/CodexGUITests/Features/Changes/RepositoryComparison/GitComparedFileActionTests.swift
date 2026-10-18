import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct GitComparedFileActionTests
{
	@Test func stagedExportUsesCapturedBlobAfterWorkingTreeChanges() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"preview.md",
			"# Before\n"
		)
		try fixture.git(["add", "preview.md"])
		try fixture.commit()
		try fixture.write(
			"preview.md",
			"# Staged\r\n"
		)
		try fixture.git(["add", "preview.md"])
		let request = GitComparisonRequest(
			owner: fixture.comparisonRequest(
				baseline: nil,
				turnID: nil
			).owner,
			repositoryRoot: fixture.root.path,
			scope: .staged,
			generation: 1
		)
		let result = await LocalGitComparisonService().compare(request)
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Comparison unavailable: \(result)")
			return
		}
		let file = try #require(snapshot.files.first)
		let controller = GitDiffDocumentController()
		let menu = controller.makeFileActionsMenu(
			file: file,
			snapshot: snapshot
		)
		let copy = try #require(menu.item(withTitle: "Copy compared contents"))
		let export = try #require(menu.item(withTitle: "Save compared version as…"))
		#expect(copy.isEnabled)
		#expect(export.isEnabled)
		let actions = controller.comparedFileActions(
			file: file,
			snapshot: snapshot
		)
		try fixture.write(
			"preview.md",
			"# Later\n"
		)
		let workspaceBytes = try Data(contentsOf: fixture.root.appendingPathComponent("preview.md"))
		let exportedBytes = try #require(await actions.loadExportBytes())
		#expect(workspaceBytes == Data("# Later\n".utf8))
		#expect(exportedBytes == Data("# Staged\r\n".utf8))
		#expect(exportedBytes != workspaceBytes)
		try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("preview.md"))
		let missingMenu = controller.makeFileActionsMenu(
			file: file,
			snapshot: snapshot
		)
		#expect(missingMenu.item(withTitle: "Open current working file in preferred editor") == nil)
		#expect(missingMenu.item(withTitle: "Save compared version as…")?.isEnabled == true)
	}
}
