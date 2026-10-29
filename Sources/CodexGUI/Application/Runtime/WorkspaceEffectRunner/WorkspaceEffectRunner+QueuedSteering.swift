import Foundation

extension WorkspaceEffectRunner
{
	func steerTransferredQueueMessage(
		_ operation: SteeringOperation,
		managedWorkspace: TaskWorkspace?
	) async throws -> String
	{
		let submission = operation.submission
		let threadID = operation.context.threadID!
		let turnID = operation.context.turnID!
		guard let path = operation.context.workspace.canonicalCheckoutPath
		else
		{
			throw AppServerError.protocolError("Queued steering requires a checkout.")
		}
		let detail = try await service.readThread(id: threadID)
		try validateConversationOwnership(
			detail.summary,
			expectedThreadID: threadID,
			expectedDirectory: URL(fileURLWithPath: path),
			workspace: managedWorkspace
		)
		guard detail.turns.contains(where:
			{
				$0.id == turnID && $0.status == "inProgress"
			})
		else
		{
			throw AppServerError.requestRejected("The captured turn is no longer active.")
		}
		// The journal is durable before deletion, and before any steering RPC can be sent.
		try await persistence.drain(projectPath: path)
		try Task.checkCancellation()
		if let entry = submission.serverQueueEntry
		{
			let current = try await service.allThreadQueue(threadID: threadID)
			guard current.contains(entry)
			else
			{
				throw AppServerError.requestRejected("Queued message changed before steering.")
			}
			try Task.checkCancellation()
			let deleted = try await service.deleteThreadQueue(
				threadID: threadID,
				queuedSubmissionID: entry.id
			)
			guard deleted
			else
			{
				throw AppServerError.requestRejected("Queued message was already consumed.")
			}
			deliver(
				.composer(.queuedSteeringDetached(operation)),
				{
				}
			)
			try await persistence.drain(projectPath: path)
		}
		try Task.checkCancellation()
		do
		{
			if let input = submission.serverQueueEntry?.inputJSON ?? submission.queuedSteeringInput
			{
				return try await service.steerQueuedInput(
					threadID: threadID,
					expectedTurnID: turnID,
					inputJSON: input
				)
			}
			return try await service.steerTurn(
				threadId: threadID,
				expectedTurnId: turnID,
				inputs: submission.inputs
			)
		}
		catch
		{
			let uncertain: Bool
			if case AppServerError.requestRejected = error
			{
				uncertain = false
			}
			else if let write = error as? ProtocolWriteFailure
			{
				uncertain = write.mayHaveBeenSent
			}
			else
			{
				uncertain = true
			}
			throw ServerQueueExecutionFailure(failure: OperationFailure(
				message: error.localizedDescription,
				outcomeIsUncertain: uncertain
			))
		}
	}
}
