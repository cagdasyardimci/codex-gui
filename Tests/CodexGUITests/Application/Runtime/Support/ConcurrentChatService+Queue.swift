import Foundation

@testable import CodexGUI

extension ConcurrentChatService
{
	func reachQueueCheckpoint(
		_ command: String,
		afterMutation: Bool
	) async
	{
		guard let checkpoint = queueCheckpoint,
				checkpoint.command == command, checkpoint.afterMutation == afterMutation
		else
		{
			return
		}
		queueCheckpointReached.signal()
		// Deliberately ignore cancellation to exercise replies from a retired request.
		await queueCheckpointRelease.wait()
	}

	func steerQueuedInput(
		threadID: String,
		expectedTurnID: String,
		inputJSON: Data
	) async throws -> String
	{
		serverQueueCalls.append("steer:\(threadID):\(expectedTurnID)")
		await reachQueueCheckpoint(
			"steer",
			afterMutation: false
		)
		serverQueueSteeredInputs.append(inputJSON)
		let values = try JSONSerialization.jsonObject(with: inputJSON) as! [[String: Any]]
		let text = values.compactMap
		{
			$0["text"] as? String
		}.joined(separator: "\n")
		let turnID = try await steerTurn(
			threadId: threadID,
			expectedTurnId: expectedTurnID,
			text: text
		)
		await reachQueueCheckpoint(
			"steer",
			afterMutation: true
		)
		if let failure = serverQueueSteerFailure
		{
			throw failure
		}
		return turnID
	}

	func threadQueuePage(
		threadID: String,
		cursor: String?,
		limit: Int?
	) async throws -> ThreadQueuePage
	{
		serverQueueCalls.append("list:\(threadID):\(cursor ?? "head")")
		if let failure = serverQueueFailure
		{
			throw failure
		}
		let entries = serverQueue[threadID] ?? []
		let offset = cursor.flatMap(Int.init) ?? 0
		let data = Array(entries.dropFirst(offset).prefix(1))
		let next = offset + data.count < entries.count ? String(offset + data.count) : nil
		if let gate = serverQueueReadGate
		{
			serverQueueReadGate = nil
			serverQueueReadStarted.signal()
			await gate.wait()
		}
		return ThreadQueuePage(
			data: data,
			nextCursor: next
		)
	}

	func addThreadQueue(
		threadID: String,
		inputJSON: Data,
		clientUserMessageID: String
	) async throws -> ThreadQueuedSubmission
	{
		serverQueueCalls.append("add:\(threadID):\(clientUserMessageID)")
		await reachQueueCheckpoint(
			"add",
			afterMutation: false
		)
		if let failure = serverQueueFailure
		{
			throw failure
		}
		let entry = try ThreadQueuedSubmission(json: [
			"id": UUID().uuidString,
			"clientUserMessageId": clientUserMessageID,
			"input": JSONSerialization.jsonObject(with: inputJSON)
		])
		serverQueue[threadID, default: []].append(entry)
		onEvent?(.threadQueueChanged(threadId: threadID))
		if turns[threadID]?.last?.status != "inProgress", !serverQueuePaused.contains(threadID)
		{
			Task
			{
				@MainActor in _ = try? await self.startThreadQueue(
					threadID: threadID,
					queuedSubmissionID: nil
				)
			}
		}
		await reachQueueCheckpoint(
			"add",
			afterMutation: true
		)
		return entry
	}

	func updateThreadQueue(
		threadID: String,
		queuedSubmissionID: String,
		inputJSON: Data
	) async throws -> ThreadQueuedSubmission
	{
		serverQueueCalls.append("update:\(threadID):\(queuedSubmissionID)")
		await reachQueueCheckpoint(
			"update",
			afterMutation: false
		)
		if let failure = serverQueueFailure
		{
			throw failure
		}
		guard let index = serverQueue[threadID]?.firstIndex(where:
			{
				$0.id == queuedSubmissionID
			}),
			let old = serverQueue[threadID]?[index]
		else
		{
			throw AppServerError.requestRejected("Queued message was consumed")
		}
		let entry = try ThreadQueuedSubmission(json: [
			"id": old.id,
			"clientUserMessageId": old.clientUserMessageID,
			"input": JSONSerialization.jsonObject(with: inputJSON)
		])
		serverQueue[threadID]?[index] = entry
		onEvent?(.threadQueueChanged(threadId: threadID))
		await reachQueueCheckpoint(
			"update",
			afterMutation: true
		)
		return entry
	}

	func deleteThreadQueue(
		threadID: String,
		queuedSubmissionID: String
	) async throws -> Bool
	{
		serverQueueCalls.append("delete:\(threadID):\(queuedSubmissionID)")
		await reachQueueCheckpoint(
			"delete",
			afterMutation: false
		)
		if let failure = serverQueueFailure
		{
			throw failure
		}
		let existing = serverQueue[threadID] ?? []
		serverQueue[threadID] = existing.filter
		{
			$0.id != queuedSubmissionID
		}
		onEvent?(.threadQueueChanged(threadId: threadID))
		await reachQueueCheckpoint(
			"delete",
			afterMutation: true
		)
		if let failure = serverQueueDeleteFailureAfterRemoval
		{
			throw failure
		}
		if serverQueueDeleteMissing
		{
			return false
		}
		return existing.contains
		{
			$0.id == queuedSubmissionID
		}
	}

	func reorderThreadQueue(
		threadID: String,
		queuedSubmissionIDs: [String]
	) async throws
	{
		serverQueueCalls.append("reorder:\(threadID)")
		if let failure = serverQueueFailure
		{
			throw failure
		}
		let entries = serverQueue[threadID] ?? []
		guard queuedSubmissionIDs.count == entries.count,
				Set(queuedSubmissionIDs) == Set(entries.map(\.id))
		else
		{
			throw AppServerError.requestRejected("Every queued ID is required")
		}
		serverQueue[threadID] = queuedSubmissionIDs
			.compactMap
			{
				id in entries.first
				{
					$0.id == id
				}
			}
		onEvent?(.threadQueueChanged(threadId: threadID))
	}

	func startThreadQueue(
		threadID: String,
		queuedSubmissionID: String?
	) async throws -> CodexTurn
	{
		serverQueueCalls.append("start:\(threadID)")
		if let failure = serverQueueFailure
		{
			throw failure
		}
		guard turns[threadID]?.last?.status != "inProgress"
		else
		{
			throw AppServerError.requestRejected("thread already has an active or pending turn")
		}
		guard let entry = queuedSubmissionID
			.flatMap(
				{
					id in serverQueue[threadID]?.first
					{
						$0.id == id
					}
				}
			) ??
			serverQueue[threadID]?.first
		else
		{
			throw AppServerError.requestRejected("Queue is empty")
		}
		serverQueue[threadID]?.removeAll
		{
			$0.id == entry.id
		}
		serverQueuePaused.remove(threadID)
		let turn = try await startTurn(
			threadId: threadID,
			text: entry.preview,
			model: nil,
			effort: nil
		)
		onEvent?(.turnStarted(
			threadId: threadID,
			turn: turn
		))
		onEvent?(.threadQueueChanged(threadId: threadID))
		return turn
	}
}
