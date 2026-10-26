import Foundation

/// A list operation must not follow a cursor it has already visited.
struct PaginationCursorTracker
{
	private var visited: Set<String> = []
	let repeatedCursorMessage: String

	init(repeatedCursorMessage: String)
	{
		self.repeatedCursorMessage = repeatedCursorMessage
	}

	mutating func advance(to cursor: String?) throws -> String?
	{
		if let cursor, !visited.insert(cursor).inserted
		{
			throw AppServerError.protocolError(repeatedCursorMessage)
		}
		return cursor
	}
}
