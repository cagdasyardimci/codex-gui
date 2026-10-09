import Foundation

struct ProjectArchiveOperation: Equatable
{
	let context: OperationContext
	let project: URL
}

struct ProjectArchiveResult
{
	let archivedThreadIDs: [String]
	let failure: OperationFailure?
}
