import Foundation

/// Keeps immutable parsed and filtered rows while the snapshot and content filters are stable.
struct GitDiffProjectionCache
{
	private struct Key: Equatable
	{
		let snapshotID: String
		let owner: FeaturePresentationOwner
		let showWordDiffs: Bool
		let ignoreWhitespace: Bool
		let ignoreImports: Bool
	}

	private static let maximumCachedFileCount = 32

	private var key: Key?
	// Git paths retain their bytes even when Swift considers their Unicode forms equivalent.
	private var rowsByFileID: [Data: [[GitDiffRow]]] = [:]
	private(set) var projectionCount = 0
	private(set) var requestCount = 0

	var cachedFileIDs: Set<String>
	{
		Set(rowsByFileID.keys.map
		{
			String(
				decoding: $0,
				as: UTF8.self
			)
		})
	}

	mutating func clear()
	{
		key = nil
		rowsByFileID.removeAll()
	}

	mutating func file(
		_ file: GitComparisonFile,
		presentation: GitDiffPresentation
	) -> GitDiffFilePresentation
	{
		requestCount += 1
		prepare(for: presentation)
		let fileIdentity = Data(file.id.utf8)
		let rows: [[GitDiffRow]]
		if let cached = rowsByFileID[fileIdentity]
		{
			rows = cached
		}
		else
		{
			rows = presentation.projectedRows(for: file)
			if rowsByFileID.count >= Self.maximumCachedFileCount,
				let evictedID = rowsByFileID.keys.first
			{
				rowsByFileID.removeValue(forKey: evictedID)
			}
			rowsByFileID[fileIdentity] = rows
			projectionCount += 1
		}
		return presentation.file(
			file,
			projectedRows: rows
		)
	}

	mutating func prepare(for presentation: GitDiffPresentation)
	{
		let nextKey = Key(
			snapshotID: presentation.snapshot.id,
			owner: presentation.snapshot.request.owner,
			showWordDiffs: presentation.options.showWordDiffs,
			ignoreWhitespace: presentation.options.ignoreWhitespace,
			ignoreImports: presentation.options.ignoreImports
		)
		if key != nextKey
		{
			key = nextKey
			rowsByFileID.removeAll()
		}
	}
}
