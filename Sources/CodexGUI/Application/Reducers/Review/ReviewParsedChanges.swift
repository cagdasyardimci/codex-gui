/// Immutable parsed changes can be shared by successive workspace snapshots.
final class ReviewParsedChanges
{
	let changes: [FileChange]
	let identities: [String]
	let files: [ReviewFile]

	init(
		changes: [FileChange],
		identities: [String],
		files: [ReviewFile]
	)
	{
		self.changes = changes
		self.identities = identities
		self.files = files
	}
}
