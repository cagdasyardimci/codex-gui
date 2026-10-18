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
		).map(\.path) == ["Sources/File.swift", "Sources/File.swift", "inside.swift"])
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
		).map(\.path) == ["file.swift", "file.swift"])
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

	@Test func comparisonProjectionNormalizesEquivalentSpellingsAndPreservesRawReports()
	{
		let paths = ["A.swift", "./A.swift", "Sources/../A.swift", "/workspace/repo/A.swift"]
		let changes = paths.map
		{
			change($0)
		}
		let projected = ReportedRepositoryFileChanges.filter(
			changes,
			repositoryRoot: "/workspace/repo/./"
		)
		#expect(projected.map(\.path) == Array(
			repeating: "A.swift",
			count: paths.count
		))
		#expect(changes.map(\.path) == paths)
		let rename = change(
			"./A.swift",
			movePath: "/workspace/repo/folder/../B.swift"
		)
		let normalizedRename = ReportedRepositoryFileChanges.filter(
			[rename],
			repositoryRoot: "/workspace/repo"
		)
		#expect(normalizedRename.first?.path == "A.swift")
		#expect(normalizedRename.first?.movePath == "B.swift")
		#expect(rename.path == "./A.swift")
	}

	@Test func lexicalProjectionKeepsByteDistinctUnicodePaths()
	{
		let paths = ["\u{00E9}.swift", "e\u{0301}.swift"]
		let projected = ReportedRepositoryFileChanges.filter(
			paths.map
			{
				change("./" + $0)
			},
			repositoryRoot: "/workspace/repo"
		)
		#expect(projected.count == 2)
		#expect(zip(
			projected,
			paths
		).allSatisfy
		{
			$0.path.utf8.elementsEqual($1.utf8)
		})
	}

	@Test func containmentUsesTheExactCheckoutRootBytes()
	{
		let composedRoot = "/workspace/\u{00E9}"
		let decomposedRoot = "/workspace/e\u{0301}"
		let paths = [composedRoot + "/File.swift", decomposedRoot + "/File.swift", "File.swift"]
		for (root, acceptedIndex) in [(composedRoot, 0), (decomposedRoot, 1)]
		{
			let projected = ReportedRepositoryFileChanges.filter(
				paths.map
				{
					change($0)
				},
				repositoryRoot: root + "/folder/../"
			)
			#expect(projected.map(\.path) == ["File.swift", "File.swift"])
			let onlyAbsolute = ReportedRepositoryFileChanges.filter(
				[change(paths[acceptedIndex]), change(paths[1 - acceptedIndex])],
				repositoryRoot: root
			)
			#expect(onlyAbsolute.count == 1)
		}
	}

	@Test func lexicalProjectionTreatsSlashAsAByteBeforeCombiningMarks()
	{
		let filename = "\u{0301}File.swift"
		let paths = [filename,
						"./" + filename,
						"folder/../" + filename,
						"\u{0301}folder/../File.swift"]
		let projected = ReportedRepositoryFileChanges.filter(
			paths.map
			{
				change($0)
			},
			repositoryRoot: "/workspace/repo"
		)
		let expected = [filename, filename, filename, "File.swift"]
		#expect(projected.count == expected.count)
		#expect(zip(
			projected,
			expected
		).allSatisfy
		{
			$0.path.utf8.elementsEqual($1.utf8)
		})
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
