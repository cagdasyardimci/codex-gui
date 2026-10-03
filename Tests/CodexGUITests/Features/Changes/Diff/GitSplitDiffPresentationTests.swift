import Foundation
import Testing

@testable import CodexGUI

struct GitSplitDiffPresentationTests
{
	@Test func contextIsCopiedToBothSidesWithoutChangingLogicalLines()
	{
		let context = GitDiffRow(
			id: "context",
			kind: .context,
			text: "let value = 1",
			oldLine: 12,
			newLine: 15
		)
		let projection = GitSplitDiffPresentation(rows: [context])
		#expect(projection.pairs.count == 1)
		#expect(projection.pairs.first?.oldRow == context)
		#expect(projection.pairs.first?.newRow == context)
		#expect(projection.pairs.first?.isGap == false)
		#expect(projection.unifiedRows == [context])
	}

	@Test func unequalReplacementAlignsInOrderAndLeavesAnEmptyOldCell()
	{
		let deletions = [
			deletion(
				"old-a",
				line: 8
			),
			deletion(
				"old-b",
				line: 9
			),
		]
		let additions = [
			addition(
				"new-a",
				line: 11
			),
			addition(
				"new-b",
				line: 12
			),
			addition(
				"new-c",
				line: 13
			),
		]
		let rows = deletions + additions
		let projection = GitSplitDiffPresentation(rows: rows)
		#expect(projection.pairs.count == 3)
		#expect(projection.pairs.map
		{
			$0.oldRow?.id
		} == ["old-a", "old-b", nil])
		#expect(projection.pairs.map
		{
			$0.newRow?.id
		} == ["new-a", "new-b", "new-c"])
		#expect(projection.pairs.map
		{
			$0.oldRow?.oldLine
		} == [8, 9, nil])
		#expect(projection.pairs.map
		{
			$0.newRow?.newLine
		} == [11, 12, 13])
		#expect(projection.unifiedRows == rows)
		#expect(!projection.pairs.contains
		{
			$0.isGap
		})
	}

	@Test func additionAndDeletionOnlyBlocksKeepOppositeCellsEmpty()
	{
		let additions = [
			addition(
				"new-a",
				line: 1
			),
			addition(
				"new-b",
				line: 2
			),
		]
		let added = GitSplitDiffPresentation(rows: additions)
		#expect(added.pairs.map(\.newRow) == additions.map(Optional.some))
		#expect(added.pairs.allSatisfy
		{
			$0.oldRow == nil
		})
		#expect(added.unifiedRows == additions)

		let deletions = [
			deletion(
				"old-a",
				line: 3
			),
			deletion(
				"old-b",
				line: 4
			),
		]
		let removed = GitSplitDiffPresentation(rows: deletions)
		#expect(removed.pairs.map(\.oldRow) == deletions.map(Optional.some))
		#expect(removed.pairs.allSatisfy
		{
			$0.newRow == nil
		})
		#expect(removed.unifiedRows == deletions)
	}

	@Test func foldedGapRetainsExpansionMetadataAndSeparatesChangeBlocks()
	{
		let before = deletion(
			"before-gap",
			line: 3
		)
		let gap = GitDiffRow(
			id: "gap",
			kind: .gap,
			text: "8 unmodified lines",
			oldLine: nil,
			newLine: nil,
			gapID: "snapshot:file:gap",
			hiddenLineCount: 8,
			canExpand: true
		)
		let after = addition(
			"after-gap",
			line: 12
		)
		let projection = GitSplitDiffPresentation(rows: [before, gap, after])
		#expect(projection.pairs.count == 3)
		#expect(projection.pairs[0].oldRow == before)
		#expect(projection.pairs[0].newRow == nil)
		#expect(projection.pairs[1].isGap)
		#expect(projection.pairs[1].oldRow == gap)
		#expect(projection.pairs[1].newRow == gap)
		#expect(projection.pairs[2].oldRow == nil)
		#expect(projection.pairs[2].newRow == after)
		#expect(projection.unifiedRows == [before, gap, after])
	}

	@Test func contextSeparatesAdjacentChangesAndRetainsEmptySourceText()
	{
		let before = deletion(
			"before",
			line: 8
		)
		let context = GitDiffRow(
			id: "blank-context",
			kind: .context,
			text: "",
			oldLine: 9,
			newLine: 8
		)
		let after = addition(
			"after",
			line: 9
		)
		let projection = GitSplitDiffPresentation(rows: [before, context, after])
		#expect(projection.pairs.count == 3)
		#expect(projection.pairs[0].newRow == nil)
		#expect(projection.pairs[1].oldRow == context)
		#expect(projection.pairs[1].newRow == context)
		#expect(projection.pairs[2].oldRow == nil)
		#expect(projection.unifiedRows == [before, context, after])
	}

	@Test func reorderedChangesPreserveUTF16RangesAndRecordIdentity() throws
	{
		let oldText = "let emoji = \"😀\"; old()"
		let newText = "let emoji = \"😀\"; new()"
		let oldRange = (oldText as NSString).range(of: "old")
		let newRange = (newText as NSString).range(of: "new")
		let old = GitDiffRow(
			id: "unicode-old",
			kind: .deletion,
			text: oldText,
			oldLine: 40,
			newLine: nil,
			changedRanges: [oldRange]
		)
		let new = GitDiffRow(
			id: "unicode-new",
			kind: .addition,
			text: newText,
			oldLine: nil,
			newLine: 44,
			changedRanges: [newRange]
		)
		let projection = GitSplitDiffPresentation(rows: [new, old])
		let pair = try #require(projection.pairs.first)
		#expect(projection.pairs.count == 1)
		#expect(pair.oldRow == old)
		#expect(pair.newRow == new)
		#expect(projection.unifiedRows == [old, new])
		#expect(oldRange.location == 18)
		#expect(newRange.location == 18)
		let preservedOld = try #require(pair.oldRow)
		let preservedNew = try #require(pair.newRow)
		#expect((preservedOld.text as NSString).substring(with: preservedOld.changedRanges[0])
			== "old")
		#expect((preservedNew.text as NSString).substring(with: preservedNew.changedRanges[0])
			== "new")
	}

	@Test func alignedDisplayRowCountDoesNotReplaceCanonicalAdditionDeletionTotals()
	{
		let rows = [
			deletion(
				"old-a",
				line: 1
			),
			deletion(
				"old-b",
				line: 2
			),
			addition(
				"new-a",
				line: 1
			),
			addition(
				"new-b",
				line: 2
			),
			addition(
				"new-c",
				line: 3
			),
		]
		let canonical = GitComparisonFile(
			oldPath: "Example.swift",
			newPath: "Example.swift",
			kind: .modified,
			additions: 3,
			deletions: 2,
			isBinary: false,
			patch: "@@ -1,2 +1,3 @@\n-old-a\n-old-b\n+new-a\n+new-b\n+new-c\n",
			hunks: []
		)
		let filePresentation = GitDiffFilePresentation(
			file: canonical,
			rows: rows
		)
		let projection = GitSplitDiffPresentation(rows: filePresentation.rows)
		#expect(projection.pairs.count == 3)
		#expect(projection.unifiedRows.count == 5)
		#expect(filePresentation.file == canonical)
		#expect(filePresentation.file.additions == 3)
		#expect(filePresentation.file.deletions == 2)
		#expect(filePresentation.rows == rows)
	}

	@Test func emptyInputProducesNoPlaceholderRecords()
	{
		let projection = GitSplitDiffPresentation(rows: [])
		#expect(projection.pairs.isEmpty)
		#expect(projection.unifiedRows.isEmpty)
	}

	private func deletion(
		_ id: String,
		line: Int
	) -> GitDiffRow
	{
		GitDiffRow(
			id: id,
			kind: .deletion,
			text: id,
			oldLine: line,
			newLine: nil
		)
	}

	private func addition(
		_ id: String,
		line: Int
	) -> GitDiffRow
	{
		GitDiffRow(
			id: id,
			kind: .addition,
			text: id,
			oldLine: nil,
			newLine: line
		)
	}
}
