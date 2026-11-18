import AppKit

enum GitReviewDesignLayout
{
	/// Proposed local presentation policy; the reference does not specify a threshold.
	static let largeFileCount = 20
	static let largeChangedLineCount = 2_000
	// Even a few files can contain dozens of independently laid out TextKit viewports.
	private static let sourceViewportLimit = 64

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
		if changedLineCount >= largeChangedLineCount
		{
			return true
		}
		return snapshot.files.count > 1 && GitDiffPresentation.reachesSourceViewportLimit(
			in: snapshot.files,
			limit: sourceViewportLimit
		)
	}
}
