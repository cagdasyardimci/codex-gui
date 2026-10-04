import Foundation

struct ProjectFileIndex: Sendable
{
	let files: [String]
	let isReusableWithProjectObservation: Bool
	private let searchableFiles: [SearchableFile]

	private struct SearchableFile: Sendable
	{
		let path: String
		let name: String
		let characterCount: Int
	}

	private struct Match
	{
		let index: Int
		let score: Int
		let characterCount: Int

		func precedes(_ other: Match) -> Bool
		{
			if score != other.score
			{
				return score < other.score
			}
			if characterCount != other.characterCount
			{
				return characterCount < other.characterCount
			}
			return index < other.index
		}
	}

	init(
		files: [String],
		isReusableWithProjectObservation: Bool = true
	)
	{
		self.files = files
		self.isReusableWithProjectObservation = isReusableWithProjectObservation
		searchableFiles = files.map
		{
			SearchableFile(
				path: $0.lowercased(),
				name: URL(fileURLWithPath: $0).lastPathComponent.lowercased(),
				characterCount: $0.count
			)
		}
	}

	func search(
		_ query: String,
		limit: Int = 12
	) -> [String]
	{
		precondition(limit >= 0)
		guard limit > 0
		else
		{
			return []
		}
		let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !normalizedQuery.isEmpty
		else
		{
			return Array(files.prefix(limit))
		}

		let capacity = min(
			limit,
			files.count
		)
		var matches: [Match] = []
		matches.reserveCapacity(capacity)
		for (index, file) in searchableFiles.enumerated()
		{
			guard let score = matchScore(
				file: file,
				query: normalizedQuery
			)
			else
			{
				continue
			}
			retain(
				Match(
					index: index,
					score: score,
					characterCount: file.characterCount
				),
				in: &matches,
				capacity: capacity
			)
		}
		return matches.sorted
		{
			$0.precedes($1)
		}.map
		{
			files[$0.index]
		}
	}

	private func matchScore(
		file: SearchableFile,
		query: String
	) -> Int?
	{
		if file.name == query
		{
			return 0
		}
		if file.name.hasPrefix(query)
		{
			return 1
		}
		if file.name.contains(query)
		{
			return 2
		}
		if file.path.hasPrefix(query)
		{
			return 3
		}
		if file.path.contains(query)
		{
			return 4
		}
		return nil
	}

	/// The root is the worst retained match, so each query stores only its requested results.
	private func retain(
		_ match: Match,
		in matches: inout [Match],
		capacity: Int
	)
	{
		if matches.count < capacity
		{
			matches.append(match)
			var child = matches.count - 1
			while child > 0
			{
				let parent = (child - 1) / 2
				guard matches[parent].precedes(matches[child])
				else
				{
					break
				}
				matches.swapAt(
					parent,
					child
				)
				child = parent
			}
			return
		}
		guard let worst = matches.first, match.precedes(worst)
		else
		{
			return
		}
		matches[0] = match
		var parent = 0
		while parent * 2 + 1 < matches.count
		{
			var child = parent * 2 + 1
			let right = child + 1
			if right < matches.count, matches[child].precedes(matches[right])
			{
				child = right
			}
			guard matches[parent].precedes(matches[child])
			else
			{
				break
			}
			matches.swapAt(
				parent,
				child
			)
			parent = child
		}
	}
}
