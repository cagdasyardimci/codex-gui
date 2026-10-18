/// Immutable parsed changes can be shared by successive workspace snapshots.
final class ReviewParsedChanges
{
	let changes: [FileChange]
	let files: [ReviewFile]

	init(
		changes: [FileChange],
		files: [ReviewFile]
	)
	{
		self.changes = changes
		self.files = files
	}
}
