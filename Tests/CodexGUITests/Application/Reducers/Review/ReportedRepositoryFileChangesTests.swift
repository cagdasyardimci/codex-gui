import Foundation
import Testing

@testable import CodexGUI

struct ReportedRepositoryFileChangesTests
{
	@Test func temporaryCopiesAndEscapingPathsAreExcluded()
	{
		let paths = [
			"Sources/File.swift",
			"/workspace/repo/Sources/File.swift",
			"/tmp/codex-gui-send.copy/Sources/File.swift",
			"/workspace/repo-other/File.swift",
			"../outside.swift",
			"Sources/../../outside.swift",
			"/workspace/repo/../outside.swift",
			"Sources/../inside.swift",
		]
		let changes = paths.map
		{
			change($0)
		}
		#expect(ReportedRepositoryFileChanges.filter(
			changes,
			repositoryRoot: "/workspace/repo/"
		).map(\.path) == [paths[0], paths[1], paths[7]])
	}

	@Test func repositoryLocatedInTemporaryDirectoryKeepsItsOwnEdits()
	{
		let paths = ["file.swift", "/tmp/repo/file.swift", "/tmp/other/file.swift"]
		#expect(ReportedRepositoryFileChanges.filter(
			paths.map
			{
				change($0)
			},
			repositoryRoot: "/tmp/repo"
		).map(\.path) == Array(paths.prefix(2)))
	}

	@Test func renamesRequireBothPathsInsideCheckout()
	{
		let internalRename = change(
			"old.swift",
			movePath: "new.swift"
		)
		let outbound = change(
			"old.swift",
			movePath: "/tmp/copy/new.swift"
		)
		let inbound = change(
			"/tmp/copy/old.swift",
			movePath: "new.swift"
		)
		#expect(ReportedRepositoryFileChanges.filter(
			[internalRename, outbound, inbound],
			repositoryRoot: "/workspace/repo"
		) == [internalRename])
	}

	@Test func unknownCheckoutPreservesReportedEdits()
	{
		let changes = [change("/tmp/copy/file.swift")]
		#expect(ReportedRepositoryFileChanges.filter(
			changes,
			repositoryRoot: nil
		) == changes)
	}

	private func change(
		_ path: String,
		movePath: String? = nil
	) -> FileChange
	{
		var kind: [String: String] = ["type": "update"]
		kind["move_path"] = movePath
		return FileChange(json: ["path": path, "kind": kind, "diff": "@@ -1 +1 @@\n-a\n+b"])!
	}
}
