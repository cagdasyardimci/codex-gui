import Foundation
import Testing

@testable import CodexGUI

struct GitDiffProjectionCacheTests
{
	@Test func projectionCacheReusesRowsAcrossGapExpansionAndResetsForContentOptions() throws
	{
		let context = (1 ... 12).map
		{
			" line \($0)"
		}.joined(separator: "\n")
		let snapshot = fixture("\(context)\n-old\n+new")
		var presentation = GitDiffPresentation(snapshot: snapshot)
		var cache = GitDiffProjectionCache()
		cache.prepare(for: presentation)
		#expect(cache.cachedFileIDs.isEmpty)
		let file = try #require(snapshot.files.first)
		let folded = cache.file(
			file,
			presentation: presentation
		)
		let gap = try #require(folded.rows.first
		{
			$0.kind == .gap
		})
		#expect(cache.projectionCount == 1)
		presentation.options.expandedGapIDs.insert(Data(try #require(gap.gapID).utf8))
		let expanded = cache.file(
			file,
			presentation: presentation
		)
		#expect(expanded.rows.count == 14)
		#expect(cache.projectionCount == 1)
		presentation.options.ignoreWhitespace = true
		cache.prepare(for: presentation)
		#expect(cache.cachedFileIDs.isEmpty)
		_ = cache.file(
			file,
			presentation: presentation
		)
		#expect(cache.projectionCount == 2)
		presentation = GitDiffPresentation(snapshot: fixture(
			"-old\n+new",
			id: "next"
		))
		cache.prepare(for: presentation)
		#expect(cache.cachedFileIDs.isEmpty)
	}

	private func fixture(
		_ content: String,
		path: String = "Sources/Test.swift",
		id: String = "snapshot"
	) -> GitComparisonSnapshot
	{
		let patch = "@@ -1 +1 @@\n" + content + "\n"
		let lines = content.components(separatedBy: "\n")
		let file = GitComparisonFile(
			oldPath: path,
			newPath: path,
			kind: .modified,
			additions: lines.filter
			{
				$0.hasPrefix("+")
			}.count,
			deletions: lines.filter
			{
				$0.hasPrefix("-")
			}.count,
			isBinary: false,
			patch: patch,
			hunks: [GitComparisonHunk(
				header: "@@ -1 +1 @@",
				text: patch,
				oldStart: 1,
				newStart: 1
			)]
		)
		return comparisonSnapshot(
			patch: patch,
			files: [file],
			id: id
		)
	}

	private func comparisonSnapshot(
		patch: String,
		files: [GitComparisonFile],
		id: String = "snapshot"
	) -> GitComparisonSnapshot
	{
		return GitComparisonSnapshot(
			request: GitComparisonRequest(
				owner: FeaturePresentationOwner(ConversationSnapshot(
					projectPath: "/neutral",
					threads: [],
					selectedThreadID: "fixture",
					entries: [],
					canLoadEarlierTurns: false,
					changedFiles: [],
					diff: "",
					draft: "",
					canSend: false,
					accountDescription: "Test",
					backendDescription: "Test",
					executionState: .ready,
					statusMessage: nil,
					models: [],
					selectedModelID: nil,
					selectedEffort: nil,
					pendingInteractions: [],
					recentProjects: []
				)),
				repositoryRoot: "/neutral/repository",
				scope: .unstaged,
				generation: 1
			),
			id: id,
			resolvedBase: "base",
			resolvedTarget: "target",
			patch: Data(patch.utf8),
			files: files
		)
	}
}
