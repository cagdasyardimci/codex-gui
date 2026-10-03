import Foundation

struct ProjectFileIndex: Sendable
{
	let files: [String]

	func search(
		_ query: String,
		limit: Int = 12
	) -> [String]
	{
		let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalizedQuery.isEmpty
		else
		{
			return Array(files.prefix(limit))
		}

		let matchingFiles = files.compactMap
		{
			path -> (path: String, score: Int)? in
			guard let score = matchScore(
				path: path,
				query: normalizedQuery
			)
			else
			{
				return nil
			}
			return (path, score)
		}
		let rankedFiles = matchingFiles.sorted
		{
			left, right in
			left.score == right.score
				? left.path.count < right.path.count
				: left.score < right.score
		}
		return rankedFiles.prefix(limit).map(\.path)
	}

	private func matchScore(
		path: String,
		query: String
	) -> Int?
	{
		let lowercasedPath = path.lowercased()
		let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
		if fileName == query
		{
			return 0
		}
		if fileName.hasPrefix(query)
		{
			return 1
		}
		if fileName.contains(query)
		{
			return 2
		}
		if lowercasedPath.hasPrefix(query)
		{
			return 3
		}
		if lowercasedPath.contains(query)
		{
			return 4
		}
		return nil
	}
}
