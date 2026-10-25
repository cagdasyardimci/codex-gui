import Foundation
import Testing

@testable import CodexGUI

struct GitSplitDiffPresentationTests
{

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
