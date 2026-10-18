import AppKit

enum GitReviewDesignLayout
{
	/// Proposed local presentation policy; the reference does not specify a threshold.
	static let largeFileCount = 20
	static let largeChangedLineCount = 2_000

	static func isLarge(_ snapshot: GitComparisonSnapshot) -> Bool
	{
		guard !snapshot.files.isEmpty
		else
		{
			return false
		}
		let hasManyFiles = snapshot.files.count >= largeFileCount
		if hasManyFiles
		{
			return true
		}
		let changedLineCount = snapshot.additions + snapshot.deletions
		return changedLineCount >= largeChangedLineCount
	}
}
