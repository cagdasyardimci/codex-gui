import Foundation

struct GitSplitDiffPair: Equatable, Sendable
{
	let oldRow: GitDiffRow?
	let newRow: GitDiffRow?

	var isGap: Bool
	{
		oldRow?.kind == .gap || newRow?.kind == .gap
	}
}

/// Aligns each contiguous change block without synthesizing source text or crossing a gap.
struct GitSplitDiffPresentation: Equatable, Sendable
{
	let pairs: [GitSplitDiffPair]
	let unifiedRows: [GitDiffRow]

	var oldRows: [GitDiffRow?]
	{
		pairs.map(\.oldRow)
	}
	var newRows: [GitDiffRow?]
	{
		pairs.map(\.newRow)
	}

	init(rows: [GitDiffRow])
	{
		var aligned: [GitSplitDiffPair] = []
		var unified: [GitDiffRow] = []
		var index = 0
		while index < rows.count
		{
			let row = rows[index]
			if row.kind == .context || row.kind == .gap
			{
				aligned.append(GitSplitDiffPair(
					oldRow: row,
					newRow: row
				))
				unified.append(row)
				index += 1
				continue
			}
			var deletions: [GitDiffRow] = []
			var additions: [GitDiffRow] = []
			while index < rows.count
			{
				let change = rows[index]
				guard change.kind == .deletion || change.kind == .addition
				else
				{
					break
				}
				if change.kind == .deletion
				{
					deletions.append(change)
				}
				else
				{
					additions.append(change)
				}
				index += 1
			}
			unified.append(contentsOf: deletions)
			unified.append(contentsOf: additions)
			for offset in 0 ..< max(
				deletions.count,
				additions.count
			)
			{
				aligned.append(GitSplitDiffPair(
					oldRow: offset < deletions.count ? deletions[offset] : nil,
					newRow: offset < additions.count ? additions[offset] : nil
				))
			}
		}
		pairs = aligned
		unifiedRows = unified
	}
}
