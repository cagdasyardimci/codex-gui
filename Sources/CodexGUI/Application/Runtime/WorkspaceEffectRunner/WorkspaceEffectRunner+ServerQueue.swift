import Foundation

extension WorkspaceEffectRunner
{
	func performServerQueue(
		_ operation: ServerQueueOperation,
		managedWorkspace: TaskWorkspace?
	) async throws -> WorkspaceAction
	{
		var mutationBegan = false
		do
		{
			try await verifyWorkspace(managedWorkspace)
			guard let path = operation.context.workspace.canonicalCheckoutPath,
					let threadID = operation.conversation.threadID
			else
			{
				throw AppServerError.protocolError("Queue operation requires a conversation.")
			}
			let project = URL(fileURLWithPath: path)
			let detail = try await service.readThread(id: threadID)
			try validateConversationOwnership(
				detail.summary,
				expectedThreadID: threadID,
				expectedDirectory: project,
				workspace: managedWorkspace
			)
			try await persistence.drain(projectPath: path)
			try Task.checkCancellation()
			var result = ServerQueueResult()
			result.consumedClientIDs = Set(detail.turns.flatMap(\.items).compactMap(\.clientID))
			var acknowledgements: Set<UUID> = []
			func accepted(_ entry: ThreadQueuedSubmission? = nil)
			{
				if let entry
				{
					acknowledgements.insert(entry.localID)
				}
				deliver(
					.composer(.serverQueueMutationAccepted(
						operation,
						entry
					)),
					{
					}
				)
			}
			switch operation.command
			{
			case .refresh: break
			case .add(let message):
				let input = try serverQueueInput(
					message,
					operation: operation,
					project: project
				)
				mutationBegan = true
				let entry = try await service.addThreadQueue(
					threadID: threadID,
					inputJSON: input,
					clientUserMessageID: message.id.uuidString
				)
				accepted(entry)
			case .update(let message):
				guard let old = operation.entries.first(where:
					{
						$0.localID == message.id
					})
				else
				{
					throw AppServerError.requestRejected("Queued message was already consumed.")
				}
				let input = try serverQueueInput(
					message,
					operation: operation,
					project: project
				)
				mutationBegan = true
				let entry = try await service.updateThreadQueue(
					threadID: threadID,
					queuedSubmissionID: old.id,
					inputJSON: input
				)
				guard entry.clientUserMessageID == old.clientUserMessageID
				else
				{
					throw AppServerError.protocolError("Queued message client identity changed.")
				}
				accepted(entry)
			case .delete(let id):
				guard let old = operation.entries.first(where:
					{
						$0.localID == id
					})
				else
				{
					throw AppServerError.requestRejected("Queued message was already consumed.")
				}
				mutationBegan = true
				let deleted = try await service.deleteThreadQueue(
					threadID: threadID,
					queuedSubmissionID: old.id
				)
				if !deleted
				{
					rememberQueueReferences(
						operation.messages.filter
						{
							$0.id == id
						},
						project: project,
						threadID: threadID
					)
				}
				accepted()
			case .reorder(let ids):
				let mapping = Dictionary(uniqueKeysWithValues: operation.entries.map
				{
					(
						$0.localID,
						$0.id
					)
				})
				let ordered = ids.compactMap
				{
					mapping[$0]
				}
				guard ordered.count == operation.entries.count,
						Set(ordered).count == ordered.count
				else
				{
					throw AppServerError.requestRejected("Queue changed before reordering.")
				}
				mutationBegan = true
				try await service.reorderThreadQueue(
					threadID: threadID,
					queuedSubmissionIDs: ordered
				)
				accepted()
			case .resume(let selectedID):
				var current = try await service.allThreadQueue(threadID: threadID)
				for message in operation.messages where message.serverID == nil
				{
					if let existing = current
						.first(where:
							{
								$0.localID == message.id
							})
					{
						accepted(existing); continue
					}
					guard message.enqueueUncertain != true
					else
					{
						throw AppServerError
							.requestRejected("Queue acceptance requires reconciliation.")
					}
					let input = try serverQueueInput(
						message,
						operation: operation,
						project: project
					)
					deliver(
						.composer(.serverQueueEnqueueBegan(
							operation,
							message.id
						)),
						{
						}
					)
					try await persistence.drain(projectPath: path)
					try Task.checkCancellation()
					mutationBegan = true
					let entry = try await service.addThreadQueue(
						threadID: threadID,
						inputJSON: input,
						clientUserMessageID: message.id.uuidString
					)
					current.append(entry)
					accepted(entry)
				}
				let latest = try await service.readThread(id: threadID)
				if !latest.turns.contains(where:
					{
						$0.status == "inProgress"
					})
				{
					let selected = selectedID
						.flatMap
						{
							id in current.first
							{
								$0.localID == id
							}?.id
						}
					mutationBegan = true
					do
					{
						result.turn = try await service.startThreadQueue(
							threadID: threadID,
							queuedSubmissionID: selected
						)
					}
					catch AppServerError.requestRejected(let message)
						where message.contains("active or pending turn") && !acknowledgements
						.isEmpty
					{
					}

				}
				result.resumed = true
				accepted()
			}
			do
			{
				let entries = try await service.allThreadQueue(threadID: threadID)
				let remaining = Set(entries.map(\.localID))
				let deletedID: UUID?
				if case .delete(let id) = operation.command
				{
					deletedID = id
				}
				else
				{
					deletedID = nil
				}
				rememberQueueReferences(
					operation.messages
						.filter
						{
							($0.serverID != nil || acknowledgements.contains($0.id) || result
								.consumedClientIDs.contains($0.id.uuidString)) && !remaining
															.contains($0.id) && $0.id != deletedID
						},
					project: project,
					threadID: threadID
				)
				result.entries = entries
			}
			catch is ThreadQueueUnsupported where !operation.isMutation
			{
				result.unsupported = true
			}
			catch
			{
				if !operation.isMutation
				{
					throw error
				}
				result.refreshFailure = OperationFailure(
					message: error.localizedDescription,
					outcomeIsUncertain: false
				)
			}
			return .composer(.serverQueueFinished(
				operation,
				.succeeded(result)
			))
		}
		catch
		{
			let uncertain: Bool
			if let write = error as? ProtocolWriteFailure
			{
				uncertain = mutationBegan && write.mayHaveBeenSent
			}
			else if case AppServerError.requestRejected = error
			{
				uncertain = false
			}
			else
			{
				uncertain = mutationBegan
			}
			throw ServerQueueExecutionFailure(failure: OperationFailure(
				message: error.localizedDescription,
				outcomeIsUncertain: uncertain
			))
		}
	}

	private func serverQueueInput(
		_ message: QueuedComposerMessage,
		operation: ServerQueueOperation,
		project: URL
	) throws -> Data
	{
		if message.steeringPhase == .ready, let input = message.steeringInputJSON
		{
			return input
		}
		guard let text = ComposerPromptText.submittedText(
			message.text,
			collaborationMode: message.collaborationMode
		)
		else
		{
			throw AppServerError.protocolError("Queued message has no input.")
		}
		let prompt = ProjectProductivity.requestText(
			context: operation.projectContext,
			draft: text
		)
		let inputs = try ComposerContextBuilder.inputs(
			text: prompt,
			items: message.context,
			project: project
		)
		var values = TurnInput.protocolValues(
			for: inputs,
			skills: message.skills
		)
		if let old = operation.entries.first(where:
			{
				$0.localID == message.id
			})
		{
			values += old.input.filter
			{
				value in
				guard let type = value["type"] as? String
				else
				{
					return true
				}
				if type == "skill"
				{
					return message.skills.isEmpty
				}
				return !["text", "localImage", "mention"].contains(type)
			}
		}
		return try JSONSerialization.data(withJSONObject: values)
	}

	private func rememberQueueReferences(
		_ messages: [QueuedComposerMessage],
		project: URL,
		threadID: String
	)
	{
		storage?.rememberSentReferences(
			messages.flatMap(\.context),
			for: project,
			threadID: threadID
		)
	}
}
