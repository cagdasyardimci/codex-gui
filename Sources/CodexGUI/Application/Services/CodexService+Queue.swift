import Foundation

extension CodexService
{
	func steerQueuedInput(
		threadID: String,
		expectedTurnID: String,
		inputJSON: Data
	) async throws -> String
	{
		throw ThreadQueueUnsupported()
	}

	var canProbeThreadQueue: Bool
	{
		false
	}
	func threadQueuePage(
		threadID: String,
		cursor: String?,
		limit: Int?
	) async throws -> ThreadQueuePage
	{
		throw ThreadQueueUnsupported()
	}
	func addThreadQueue(
		threadID: String,
		inputJSON: Data,
		clientUserMessageID: String
	) async throws
		-> ThreadQueuedSubmission
	{
		throw ThreadQueueUnsupported()
	}
	func updateThreadQueue(
		threadID: String,
		queuedSubmissionID: String,
		inputJSON: Data
	) async throws -> ThreadQueuedSubmission
	{
		throw ThreadQueueUnsupported()
	}
	func deleteThreadQueue(
		threadID: String,
		queuedSubmissionID: String
	) async throws -> Bool
	{
		throw ThreadQueueUnsupported()
	}
	func reorderThreadQueue(
		threadID: String,
		queuedSubmissionIDs: [String]
	) async throws
	{
		throw ThreadQueueUnsupported()
	}
	func startThreadQueue(
		threadID: String,
		queuedSubmissionID: String?
	) async throws -> CodexTurn
	{
		throw ThreadQueueUnsupported()
	}

	func allThreadQueue(threadID: String) async throws -> [ThreadQueuedSubmission]
	{
		var cursor: String?
		var tracker =
			PaginationCursorTracker(repeatedCursorMessage: "Queue pagination repeated its cursor.")
		var result: [ThreadQueuedSubmission] = []
		var ids: Set<String> = []
		var clientIDs: Set<UUID> = []
		repeat
		{
			let page = try await threadQueuePage(
				threadID: threadID,
				cursor: cursor,
				limit: 100
			)
			for item in page.data
			{
				guard ids.insert(item.id).inserted, clientIDs.insert(item.localID).inserted
				else
				{
					throw AppServerError.protocolError("Queue changed during pagination.")
				}
				result.append(item)
			}
			cursor = try tracker.advance(to: page.nextCursor)
		}
		while cursor != nil
		return result
	}
}
