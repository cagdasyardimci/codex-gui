import Foundation

/// View inputs for the navigator. Diff options and patch text cannot change its rows.
struct GitDiffTreeRenderInputs
{
	let owner: FeaturePresentationOwner?
	let snapshotID: String
	let repositoryRoot: String
	private let files: [FileMetadata]
	let filter: String
	let expandedDirectories: Set<Data>
	let selectedFileID: String?

	init(
		state: GitReviewState,
		snapshot: GitComparisonSnapshot,
		displayedFileID: String?
	)
	{
		owner = state.owner
		snapshotID = snapshot.id
		repositoryRoot = snapshot.request.repositoryRoot
		files = snapshot.files.map(FileMetadata.init)
		filter = state.filter
		expandedDirectories = state.expandedDirectories
		selectedFileID = state.selectedFileID ?? displayedFileID
	}

	func matches(
		state: GitReviewState,
		snapshot: GitComparisonSnapshot,
		displayedFileID: String?
	) -> Bool
	{
		owner == state.owner
			&& Self.sameBytes(
				snapshotID,
				snapshot.id
			)
			&& Self.sameBytes(
				repositoryRoot,
				snapshot.request.repositoryRoot
			)
			&& Self.sameBytes(
				filter,
				state.filter
			)
			&& expandedDirectories == state.expandedDirectories
			&& Self.sameBytes(
				selectedFileID,
				state.selectedFileID ?? displayedFileID
			)
			&& files.count == snapshot.files.count
			&& zip(
				files,
				snapshot.files
			).allSatisfy
			{
				$0.matches($1)
			}
	}

	/// Keep only navigator metadata so an equal tree cannot retain an older diff's patch/hunks.
	private struct FileMetadata
	{
		let oldPath: String?
		let newPath: String?
		let kind: GitComparisonChangeKind
		let isBinary: Bool
		let additions: Int
		let deletions: Int

		init(_ file: GitComparisonFile)
		{
			oldPath = file.oldPath
			newPath = file.newPath
			kind = file.kind
			isBinary = file.isBinary
			additions = file.additions
			deletions = file.deletions
		}

		func matches(_ file: GitComparisonFile) -> Bool
		{
			sameBytes(
				oldPath,
				file.oldPath
			) && sameBytes(
				newPath,
				file.newPath
			)
				&& kind == file.kind && isBinary == file.isBinary
				&& additions == file.additions && deletions == file.deletions
		}
	}

	private static func sameBytes(
		_ lhs: String?,
		_ rhs: String?
	) -> Bool
	{
		switch (lhs, rhs)
		{
		case (nil, nil): true
		case let (lhs?, rhs?): lhs.utf8.elementsEqual(rhs.utf8)
		default: false
		}
	}
}
