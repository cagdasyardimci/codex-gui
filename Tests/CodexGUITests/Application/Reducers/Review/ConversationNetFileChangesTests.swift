import Foundation
import Testing

@testable import CodexGUI

struct ConversationNetFileChangesTests
{
	@Test func successiveEditsKeepOnlyTheNetPatchAndRevertedEditsDisappear()
	{
		let first = change("@@ -1 +1 @@\n-before\n+intermediate")
		let second = change("@@ -1 +1 @@\n-intermediate\n+after")
		#expect(ConversationNetFileChanges.merge([first, second]).map(\.diff)
			== ["@@ -1,1 +1,1 @@\n-before\n+after"])
		let reverted = change("@@ -1 +1 @@\n-intermediate\n+before")
		#expect(ConversationNetFileChanges.merge([first, reverted]).isEmpty)
	}

	@Test func creationAndDeletionCancelWhileExistingDeletionRetainsOriginalContent()
	{
		let added = change(
			"temporary\n",
			kind: "add"
		)
		let deleted = change(
			"temporary\n",
			kind: "delete"
		)
		#expect(ConversationNetFileChanges.merge([added, deleted]).isEmpty)
		let updated = change("@@ -1 +1 @@\n-original\n+temporary")
		#expect(ConversationNetFileChanges.merge([updated, deleted]).map(\.diff)
			== ["@@ -1,1 +0,0 @@\n-original"])
	}

	@Test func renamesFollowDestinationPathsAndRenameReversalHasNoNetChange()
	{
		let first = change(
			"",
			path: "first",
			movePath: "second"
		)
		let second = change(
			"",
			path: "second",
			movePath: "third"
		)
		let merged = ConversationNetFileChanges.merge([first, second])
		#expect(merged.count == 1)
		#expect(merged.first?.path == "first")
		#expect(merged.first?.movePath == "third")
		#expect(merged.first?.diff == "")
		let reverse = change(
			"",
			path: "second",
			movePath: "first"
		)
		#expect(ConversationNetFileChanges.merge([first, reverse]).isEmpty)
	}

	@Test func highCoordinatesRetainReportedHistoryWithoutMaterializingThePrefix()
	{
		let first = change("@@ -1000000 +1000000 @@\n-before\n+intermediate")
		let second = change("@@ -1000000 +1000000 @@\n-intermediate\n+after")
		#expect(ConversationNetFileChanges.merge([first, second]).map(\.diff)
			== [first.diff + "\n" + second.diff])
	}

	@Test func recreatingAVacatedRenamePathKeepsTheTwoFilesIndependent()
	{
		let renamed = change(
			"",
			path: "original.swift",
			movePath: "renamed.swift"
		)
		let recreated = change(
			"new content\n",
			kind: "add",
			path: "original.swift"
		)
		let merged = ConversationNetFileChanges.merge([renamed, recreated])
		#expect(merged.count == 2)
		#expect(merged.first?.movePath == "renamed.swift")
		#expect(merged.first?.diff == "")
		#expect(merged.last?.kind == "add")
		#expect(merged.last?.path == "original.swift")
		#expect(merged.last?.movePath == nil)
		#expect(merged.last?.diff == "@@ -0,0 +1,1 @@\n+new content")
	}

	@Test func extremeCoordinatesCannotOverflowCompositionArithmetic()
	{
		let patch = "@@ -\(Int.max),2 +\(Int.max),2 @@\n-a\n-b\n+c\n+d"
		#expect(ConversationNetFileChanges.merge([change(patch)]).map(\.diff) == [patch])
	}

	@Test func incompatibleDestinationCoordinatesRetainTheReportedPatch()
	{
		let patch = "@@ -1 +\(Int.max) @@\n-before\n+after"
		#expect(ConversationNetFileChanges.merge([change(patch)]).map(\.diff) == [patch])
	}

	@Test func expensiveDifferenceRetainsEveryReportedLine()
	{
		let count = 2_000
		let before = (0 ..< count).map
		{
			"-before-\($0)"
		}
		let after = (0 ..< count).map
		{
			"+after-\($0)"
		}
		let first = change((["@@ -1,\(count) +1,\(count) @@"] + before + after)
			.joined(separator: "\n"))
		let second = change("@@ -1 +1 @@\n-after-0\n+final-0")
		#expect(ConversationNetFileChanges.merge([first, second]).map(\.diff)
			== [first.diff + "\n" + second.diff])
	}

	@Test func unchangedPrefixAndSuffixDoNotForceTheExpensiveDifferenceFallback()
	{
		let first = change("@@ -8000 +8000 @@\n-before\n+intermediate")
		let second = change("@@ -8000 +8000 @@\n-intermediate\n+after")
		#expect(ConversationNetFileChanges.merge([first, second]).map(\.diff)
			== ["@@ -8000,1 +8000,1 @@\n-before\n+after"])
	}

	@Test func incompleteHistoryAndFinalNewlineChangesArePreserved()
	{
		let first = change("@@ -1 +1 @@\n-before\n+intermediate")
		let incompatible = change("@@ -1 +1 @@\n-unreported\n+after")
		#expect(ConversationNetFileChanges.merge([first, incompatible]).map(\.diff)
			== [first.diff + "\n" + incompatible.diff])
		let newline = change("@@ -1 +1 @@\n-a\n+b\n\\ No newline at end of file")
		#expect(ConversationNetFileChanges.merge([newline]).map(\.diff) == [newline.diff])
	}

	@Test func hunkBudgetRetainsFullHistory()
	{
		let changes = (0 ..< 257).map
		{
			change("@@ -1 +1 @@\n-value-\($0)\n+value-\($0 + 1)")
		}
		#expect(ConversationNetFileChanges.merge(changes).map(\.diff)
			== [changes.map(\.diff).joined(separator: "\n")])
	}

	@Test func canonicallyEquivalentLineChangesRetainTheirExactBytes()
	{
		let before = "\u{00E9}"
		let after = "e\u{0301}"
		#expect(before == after)
		let merged = ConversationNetFileChanges.merge([
			change("@@ -1 +1 @@\n-\(before)\n+\(after)")
		])
		#expect(merged.count == 1)
		#expect(merged.first?.diff.utf8.elementsEqual(
			"@@ -1,1 +1,1 @@\n-\(before)\n+\(after)".utf8
		) == true)
	}

	@Test func canonicallyEquivalentPathsAreIndependentReportedFiles()
	{
		let first = change(
			"@@ -1 +1 @@\n-a\n+b",
			path: "\u{00E9}.swift"
		)
		let second = change(
			"@@ -1 +1 @@\n-b\n+c",
			path: "e\u{0301}.swift"
		)
		let merged = ConversationNetFileChanges.merge([first, second])
		#expect(merged.count == 2)
		#expect(merged.first?.path.utf8.elementsEqual(first.path.utf8) == true)
		#expect(merged.last?.path.utf8.elementsEqual(second.path.utf8) == true)
	}

	@Test func exactCompositionRejectsInterleavedAndOverBudgetHistories()
	{
		let first = change("@@ -1 +1 @@\n-before\n+intermediate")
		let second = change("@@ -1 +1 @@\n-intermediate\n+after")
		#expect(ConversationNetFileChanges.mergeExactly([first, second])?.first?.diff
			== "@@ -1,1 +1,1 @@\n-before\n+after")
		let external = change("@@ -1 +1 @@\n-another task\n+after")
		#expect(ConversationNetFileChanges.mergeExactly([first, external]) == nil)
		let high = change("@@ -1000000 +1000000 @@\n-before\n+after")
		#expect(ConversationNetFileChanges.mergeExactly([high]) != nil)
		#expect(ConversationNetFileChanges.mergeExactly([high, high]) == nil)
	}

	private func change(
		_ diff: String,
		kind: String = "update",
		path: String = "file.swift",
		movePath: String? = nil
	) -> FileChange
	{
		var metadata: [String: String] = ["type": kind]
		metadata["move_path"] = movePath
		return FileChange(json: ["path": path, "kind": metadata, "diff": diff])!
	}
}
