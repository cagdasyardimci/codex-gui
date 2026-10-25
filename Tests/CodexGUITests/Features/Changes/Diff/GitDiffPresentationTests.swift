import Foundation
import Testing

@testable import CodexGUI

struct GitDiffPresentationTests
{

	@Test func patchLineClassificationDistinguishesHeadersFromRepeatedSourceMarkers() throws
	{
		let patch = "diff --git a/counter b/counter\n--- a/counter\n+++ b/counter\n"
			+ "@@ -1 +1 @@\n---counter;\n+++counter;\n"
			+ "diff --git a/next b/next\n--- a/next\n+++ b/next\n"
		let lines = GitDiffPresentation.patchLines(in: patch)
		#expect(lines.map(\.kind) == [
			.metadata,
			.metadata,
			.metadata,
			.hunkHeader,
			.source(.deletion),
			.source(.addition),
			.metadata,
			.metadata,
			.metadata,
			.metadata
		])
		let source = patch as NSString
		for line in lines
		{
			#expect(source.substring(with: line.range).utf8.elementsEqual(line.text.utf8))
		}
		let snapshot = comparisonSnapshot(
			patch: patch,
			files: GitComparisonPatchParser.files(in: Data(patch.utf8))
		)
		let rows = try #require(GitDiffPresentation(snapshot: snapshot).file("counter")).rows
		#expect(rows.map(\.kind) == [.deletion, .addition])
		#expect(rows.map(\.text) == ["--counter;", "++counter;"])
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
