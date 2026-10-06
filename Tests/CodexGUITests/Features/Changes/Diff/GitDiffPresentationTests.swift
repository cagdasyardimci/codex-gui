import Foundation
import Testing

@testable import CodexGUI

struct GitDiffPresentationTests
{
	@Test func parsedHunksKeepSourceAndDestinationLineNumbers() throws
	{
		let patch = "diff --git a/Sources/Test.swift b/Sources/Test.swift\n"
			+ "--- a/Sources/Test.swift\n+++ b/Sources/Test.swift\n"
			+ "@@ -7,3 +13,3 @@ first\n context\n-old\n+new\n tail\n"
			+ "@@ -21,0 +28,2 @@ insertion\n+first addition\n+second addition\n"
			+ "@@ -34,2 +41,0 @@ deletion\n-first removal\n-second removal\n"
		let snapshot = comparisonSnapshot(
			patch: patch,
			files: GitComparisonPatchParser.files(in: Data(patch.utf8))
		)
		let presentation = GitDiffPresentation(snapshot: snapshot)
		let rows = try #require(presentation.file("Sources/Test.swift")).rows
		#expect(rows.map(\.kind) == [
			.context,
			.deletion,
			.addition,
			.context,
			.addition,
			.addition,
			.deletion,
			.deletion,
		])
		#expect(rows.map(\.oldLine) == [7, 8, nil, 9, nil, nil, 34, 35])
		#expect(rows.map(\.newLine) == [13, nil, 14, 15, 28, 29, nil, nil])
		#expect(presentation.snapshot.patch == Data(patch.utf8))
	}

	@Test func parsedCreatedAndDeletedFilesNumberOnlyTheirExistingSide() throws
	{
		let patch = "diff --git a/created.txt b/created.txt\nnew file mode 100644\n"
			+ "--- /dev/null\n+++ b/created.txt\n@@ -0,0 +1,2 @@\n+first\n+second\n"
			+ "diff --git a/deleted.txt b/deleted.txt\ndeleted file mode 100644\n"
			+ "--- a/deleted.txt\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-first\n-second\n"
		let snapshot = comparisonSnapshot(
			patch: patch,
			files: GitComparisonPatchParser.files(in: Data(patch.utf8))
		)
		let presentation = GitDiffPresentation(snapshot: snapshot)
		let createdRows = try #require(presentation.file("created.txt")).rows
		#expect(createdRows.map(\.kind) == [.addition, .addition])
		#expect(createdRows.map(\.oldLine) == [nil, nil])
		#expect(createdRows.map(\.newLine) == [1, 2])
		let deletedRows = try #require(presentation.file("deleted.txt")).rows
		#expect(deletedRows.map(\.kind) == [.deletion, .deletion])
		#expect(deletedRows.map(\.oldLine) == [1, 2])
		#expect(deletedRows.map(\.newLine) == [nil, nil])
	}

	@Test func gapExpansionUsesSnapshotAndPreservesLogicalLineNumbers() throws
	{
		let context = (1 ... 12).map
		{
			" line \($0)"
		}.joined(separator: "\n")
		let snapshot = fixture("\(context)\n-old\n+new")
		var presentation = GitDiffPresentation(snapshot: snapshot)
		let folded = try #require(presentation.file("Sources/Test.swift"))
		let gap = try #require(folded.rows.first
		{
			$0.kind == .gap
		})
		#expect(gap.hiddenLineCount == 6)
		#expect(gap.canExpand)
		#expect(folded.rows.filter
		{
			$0.kind == .context
		}.count == 6)
		#expect(folded.rows.last?.newLine == 13)
		presentation.options.expandedGapIDs.insert(try #require(gap.gapID))
		let expanded = try #require(presentation.file("Sources/Test.swift"))
		#expect(expanded.rows.count == 14)
		#expect(expanded.rows[5].oldLine == 6)
		#expect(expanded.rows[5].newLine == 6)
		#expect(presentation.snapshot.patch == snapshot.patch)
		presentation.options.loadFullFiles = false
		let unavailable = try #require(presentation.file("Sources/Test.swift"))
		#expect(unavailable.rows.contains
		{
			$0.kind == .gap && !$0.canExpand
		})
	}

	@Test func sixContextLinesRemainUnfoldedAndGapIDsAreSnapshotScoped() throws
	{
		let six = (1 ... 6).map
		{
			" context \($0)"
		}.joined(separator: "\n")
		let presentation = GitDiffPresentation(snapshot: fixture("\(six)\n+added"))
		let file = try #require(presentation.file("Sources/Test.swift"))
		#expect(!file.rows.contains
		{
			$0.kind == .gap
		})
		let seven = six + "\n seventh\n+added"
		let first = GitDiffPresentation(snapshot: fixture(
			seven,
			id: "first"
		))
		let second = GitDiffPresentation(snapshot: fixture(
			seven,
			id: "second"
		))
		let firstID = first.file("Sources/Test.swift")?.rows.first
		{
			$0.kind == .gap
		}?.id
		let secondID = second.file("Sources/Test.swift")?.rows.first
		{
			$0.kind == .gap
		}?.id
		#expect(firstID != secondID)
	}

	@Test func whitespaceFilteringPreservesRealChangesAndRawTotals() throws
	{
		let snapshot = fixture("-let a = 1\n-let b = 2\n+let a=1\n+let b = 3")
		var presentation = GitDiffPresentation(snapshot: snapshot)
		presentation.options.ignoreWhitespace = true
		let file = try #require(presentation.file("Sources/Test.swift"))
		#expect(file.rows.filter
		{
			$0.kind == .deletion
		}.map(\.text) == ["let b = 2"])
		#expect(file.rows.filter
		{
			$0.kind == .addition
		}.map(\.text) == ["let b = 3"])
		#expect(file.rows.first
		{
			$0.kind == .context
		}?.oldLine == 1)
		#expect(snapshot.additions == 2)
		#expect(snapshot.deletions == 2)
		#expect(presentation.snapshot.patch == snapshot.patch)
	}

	@Test func wordSpansUseUTF16OffsetsWithoutHighlightingUnchangedTokens() throws
	{
		let presentation = GitDiffPresentation(
			snapshot: fixture("-let emoji = \"😀\"; old()\n+let emoji = \"😀\"; new()")
		)
		let rows = try #require(presentation.file("Sources/Test.swift")).rows
		#expect(rows.count == 2)
		for (row, expected) in zip(
			rows,
			["old", "new"]
		)
		{
			let range = try #require(row.changedRanges.first)
			#expect((row.text as NSString).substring(with: range) == expected)
			#expect(range.location == 18)
		}
	}

	@Test func wordDiffLineLimitKeepsItsExactBoundaryAndWholeLineUTF16Ranges() throws
	{
		let prefix = String(
			repeating: "a ",
			count: 1023
		)
		let old = prefix + "old "
		let new = prefix + "new "
		let boundary = GitDiffPresentation(snapshot: fixture("-\(old)\n+\(new)"))
		let boundaryRows = try #require(boundary.file("Sources/Test.swift")).rows
		#expect(boundaryRows.map(\.changedRanges) == [
			[NSRange(
				location: 2046,
				length: 3
			)],
			[NSRange(
				location: 2046,
				length: 3
			)],
		])

		for (oldText, newText) in [(old + "😀", new), (old, new + "😀")]
		{
			let oversized = GitDiffPresentation(snapshot: fixture("-\(oldText)\n+\(newText)"))
			let rows = try #require(oversized.file("Sources/Test.swift")).rows
			#expect(rows.map(\.changedRanges) == [
				[NSRange(
					location: 0,
					length: (oldText as NSString).length
				)],
				[NSRange(
					location: 0,
					length: (newText as NSString).length
				)],
			])
		}
	}

	@Test func oversizedWordDiffLinesLeaveTheFileBudgetForFollowingPairs() throws
	{
		let oversized = String(
			repeating: "+",
			count: 16_384
		)
		let prefix = String(
			repeating: "a ",
			count: 1023
		)
		let old = prefix + "old "
		let new = prefix + "new "
		var blocks = ["-\(oversized)\n+😀"]
		blocks.append(contentsOf: (0 ..< 4).map
		{
			_ in "-\(old)\n+\(new)"
		})
		blocks.append("-old tail()\n+new tail()")
		let presentation = GitDiffPresentation(snapshot: fixture(blocks.joined(separator: "\n")))
		let rows = try #require(presentation.file("Sources/Test.swift")).rows
		#expect(rows.count == 12)
		#expect(rows[0].changedRanges == [NSRange(
			location: 0,
			length: oversized.utf16.count
		)])
		#expect(rows[1].changedRanges == [NSRange(
			location: 0,
			length: 2
		)])
		for row in rows[2 ..< 10]
		{
			#expect(row.changedRanges == [NSRange(
				location: 2046,
				length: 3
			)])
		}
		for row in rows[10 ..< 12]
		{
			#expect(row.changedRanges == [NSRange(
				location: 0,
				length: row.text.utf16.count
			)])
		}
	}

	@Test func aPairBeyondTheRemainingWordBudgetDoesNotConsumeTheRemainder() throws
	{
		let prefix = String(
			repeating: "a ",
			count: 1023
		)
		var blocks = (0 ..< 3).map
		{
			_ in "-\(prefix)old \n+\(prefix)new "
		}
		let shorterPrefix = String(
			repeating: "a ",
			count: 1022
		)
		blocks.append("-\(shorterPrefix)old \n+\(shorterPrefix)new ")
		blocks.append("-call old\n+call new")
		blocks.append("-old!\n+new!")
		let presentation = GitDiffPresentation(snapshot: fixture(blocks.joined(separator: "\n")))
		let rows = try #require(presentation.file("Sources/Test.swift")).rows
		#expect(rows.count == 12)
		#expect(rows[8].changedRanges == [NSRange(
			location: 0,
			length: 8
		)])
		#expect(rows[9].changedRanges == [NSRange(
			location: 0,
			length: 8
		)])
		#expect(rows[10].changedRanges == [NSRange(
			location: 0,
			length: 3
		)])
		#expect(rows[11].changedRanges == [NSRange(
			location: 0,
			length: 3
		)])
	}

	@Test func importFilteringUsesLimitedLanguageSyntaxAndRetainsMultilineSource() throws
	{
		var swift = GitDiffPresentation(snapshot: fixture("-import Alpha\n+import Beta\n+work()"))
		swift.options.ignoreImports = true
		#expect(swift.file("Sources/Test.swift")?.rows.map(\.text) == ["work()"])
		var python = GitDiffPresentation(
			snapshot: fixture(
				"-from alpha import value\n+import beta as b\n+run()",
				path: "test.py"
			)
		)
		python.options.ignoreImports = true
		#expect(python.file("test.py")?.rows.map(\.text) == ["run()"])
		var unknown = GitDiffPresentation(
			snapshot: fixture(
				"-import Alpha\n+import Beta",
				path: "test.txt"
			)
		)
		unknown.options.ignoreImports = true
		#expect(unknown.file("test.txt")?.rows.count == 2)
		var multiline = GitDiffPresentation(
			snapshot: fixture(" \"\"\"\n-import Alpha\n+import Beta\n \"\"\"")
		)
		multiline.options.ignoreImports = true
		#expect(multiline.file("Sources/Test.swift")?.rows.count == 4)
	}

	@Test func treeFilteringRetainsAncestryAndExpansionControlsVisibility()
	{
		let snapshot = fixture(
			"-old\n+new",
			path: "Sources/Nested/Test.swift"
		)
		let presentation = GitDiffPresentation(snapshot: snapshot)
		#expect(presentation.treeRows().map(\.path) == ["Sources"])
		let expanded = presentation.treeRows(expandedDirectories: ["Sources", "Sources/Nested"])
		#expect(expanded.map(\.depth) == [0, 1, 2])
		#expect(expanded.last?.fileID == "Sources/Nested/Test.swift")
		let filtered = presentation.treeRows(filter: "TEST")
		#expect(filtered.map(\.path) == ["Sources", "Sources/Nested", "Sources/Nested/Test.swift"])
		#expect(filtered.last?.id == expanded.last?.id)
		#expect(presentation.treeRows(filter: "absent").isEmpty)
	}

	@Test func blankLinesAndUnicodeSeparatorsRemainLogicalSourceRows() throws
	{
		let presentation = GitDiffPresentation(snapshot: fixture(" \n-old\u{2028}line\n+new"))
		let rows = try #require(presentation.file("Sources/Test.swift")).rows
		#expect(rows.count == 3)
		#expect(rows[0].text.isEmpty)
		#expect(rows[1].text == "old\u{2028}line")
		#expect(rows[1].oldLine == 2)
		#expect(rows[2].newLine == 2)
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
