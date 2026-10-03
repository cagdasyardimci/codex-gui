import Foundation

@testable import CodexGUI

struct DesignPreviewGitService: GitComparisonService
{
	static let fileCount = 22

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let files = (0 ..< Self.fileCount).map
		{
			index in
			let path = "Sources/Examples/Example\(index + 1).swift"
			let patch = "@@ -1,2 +1,3 @@\n"
				+ "-let title = \"Before\"\n-let visible = false\n"
				+ "+let title = \"Example \(index + 1)\"\n+let visible = true\n"
				+ "+let detail = \"Fixture content\"\n"
			return GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 3,
				deletions: 2,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1,2 +1,3 @@",
					text: patch,
					oldStart: 1,
					newStart: 1
				)]
			)
		}
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "offline-design-comparison",
			resolvedBase: "fixture-base",
			resolvedTarget: "fixture-target",
			patch: Data(files.map(\.patch).joined(separator: "\n").utf8),
			files: files
		))
	}
}
