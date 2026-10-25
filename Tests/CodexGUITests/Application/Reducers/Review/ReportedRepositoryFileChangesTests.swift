import Foundation
import Testing

@testable import CodexGUI

struct ReportedRepositoryFileChangesTests
{

	@Test func unknownCheckoutPreservesReportedEdits()
	{
		let changes = [change("/tmp/copy/file.swift")]
		#expect(ReportedRepositoryFileChanges.filter(
			changes,
			repositoryRoot: nil
		) == changes)
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
