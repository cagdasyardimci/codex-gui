import Foundation

@testable import CodexGUI

struct GitComparisonViewFixtureService: GitComparisonService
{
	var paths = ["Sources/One.swift", "Tests/Two.swift"]
	var additions = 1
	var kind = GitComparisonChangeKind.modified

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let long = String(
			repeating: "wide source ",
			count: 60
		)
		let files = paths.map
		{
			path in
			let context = (1 ... 12).map
			{
				" \(path) \(long)\($0)"
			}.joined(separator: "\n")
			let patch = "@@ -1,13 +1,13 @@\n\(context)\n-before\n+after\n"
			return GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: kind,
				additions: additions,
				deletions: 1,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1,13 +1,13 @@",
					text: patch,
					oldStart: 1,
					newStart: 1
				)]
			)
		}
		let patch = files.map(\.patch).joined(separator: "\n")
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "reuse-fixture",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(patch.utf8),
			files: files
		))
	}
}
