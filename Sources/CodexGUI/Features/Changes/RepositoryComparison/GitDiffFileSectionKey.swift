import Foundation

/// A section depends only on its own context gaps within an immutable owned snapshot.
struct GitDiffFileSectionKey: Equatable
{
	let owner: FeaturePresentationOwner
	let snapshotID: String
	let fileID: Data
	let isCollapsed: Bool
	let options: GitDiffPresentationOptions

	init(
		file: GitComparisonFile,
		presentation: GitDiffPresentation,
		isCollapsed: Bool
	)
	{
		owner = presentation.snapshot.request.owner
		snapshotID = presentation.snapshot.id
		fileID = Data(file.id.utf8)
		self.isCollapsed = isCollapsed
		let gapPatterns = file.hunks.indices.map
		{
			GapIdentifierPattern(hunkID: "\(presentation.snapshot.id):\(file.id):\($0)")
		}
		var fileOptions = presentation.options
		fileOptions.expandedGapIDs = Set(fileOptions.expandedGapIDs.filter
		{
			gapID in
			return gapPatterns.contains
			{
				$0.matches(gapID)
			}
		})
		options = fileOptions
	}

	private struct GapIdentifierPattern
	{
		let prefix: Data
		let rowSeparator: Data

		init(hunkID: String)
		{
			prefix = Data("\(hunkID):gap:\(hunkID):".utf8)
			rowSeparator = Data(":\(hunkID):".utf8)
		}

		func matches(_ identifier: Data) -> Bool
		{
			// Paths can contain colons; a leading hunk prefix alone does not establish ownership.
			guard identifier.starts(with: prefix)
			else
			{
				return false
			}
			let boundaries = identifier.dropFirst(prefix.count)
			guard let separator = boundaries.range(of: rowSeparator)
			else
			{
				return false
			}
			return Self.isRowIndex(boundaries[..<separator.lowerBound])
				&& Self.isRowIndex(boundaries[separator.upperBound...])
		}

		private static func isRowIndex(_ bytes: Data) -> Bool
		{
			!bytes.isEmpty && bytes.allSatisfy
			{
				$0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")
			}
		}
	}
}
