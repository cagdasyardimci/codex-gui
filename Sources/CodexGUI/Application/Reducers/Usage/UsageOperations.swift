import Foundation

struct UsageReadOperation: Equatable
{
	let context: OperationContext
	let attempt: Int
}

struct UsageDeadlineOperation: Equatable
{
	let read: UsageReadOperation
	let fetchedAt: Date
	let deadline: Date
}
