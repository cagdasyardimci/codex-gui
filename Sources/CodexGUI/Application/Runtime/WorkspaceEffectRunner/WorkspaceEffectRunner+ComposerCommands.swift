import Foundation

extension WorkspaceEffectRunner
{
	func performComposerCommand(
		_ effect: WorkspaceEffect,
		context: OperationContext,
		managedWorkspace: TaskWorkspace?
	) async -> WorkspaceAction
	{
		// Ownership and checkout validation finish before a mutation can be sent.
		do
		{
			do
			{
				_ = try await readConversation(
					context,
					managedWorkspace: managedWorkspace
				)
			}
			catch
			{
				guard case .forkConversation = effect,
						ConversationLock.isAnotherApp(error.localizedDescription),
						let threadID = context.threadID,
						let path = context.workspace.canonicalCheckoutPath
				else
				{
					throw error
				}
				// A locked thread may reject reads. The list still validates its
				// checkout before the fork request is sent.
				let threads = try await service.threads(for: URL(fileURLWithPath: path))
				guard threads.contains(where:
					{
						$0.id == threadID
					})
				else
				{
					throw error
				}
			}
		}
		catch
		{
			return failureAction(
				for: effect,
				context: context,
				failure: OperationFailure(
					message: error.localizedDescription,
					outcomeIsUncertain: false
				)
			)
		}
		var mutationSent = false
		do
		{
			guard let threadID = context.threadID,
					let path = context.workspace.canonicalCheckoutPath
			else
			{
				throw AppServerError
					.protocolError("A command requires a saved chat in this checkout.")
			}
			let directory = URL(fileURLWithPath: path)
			switch effect
			{
			case .forkConversation(let request):
				mutationSent = true
				let detail = try await service.forkThread(
					id: threadID,
					expectedDirectory: directory
				)
				return .composerCommand(.forkFinished(
					request,
					.succeeded(detail)
				))
			case .compactConversation(let operation):
				_ = try await service.resumeThread(
					id: threadID,
					expectedDirectory: directory
				)
				mutationSent = true
				try await service.compactThread(id: threadID)
				return .composerCommand(.compactAcknowledged(
					operation,
					.succeeded(())
				))
			case .startConversationReview(let operation):
				guard case .review(let target) = operation.kind
				else
				{
					throw AppServerError.protocolError("A review command requires a review target.")
				}
				_ = try await service.resumeThread(
					id: threadID,
					expectedDirectory: directory
				)
				mutationSent = true
				let started = try await service.startReview(
					threadId: threadID,
					target: target,
					delivery: .inline
				)
				return .composerCommand(.reviewAcknowledged(
					operation,
					.succeeded(started)
				))
			case .updateCommandSettings(let operation):
				_ = try await service.resumeThread(
					id: threadID,
					expectedDirectory: directory
				)
				mutationSent = true
				try await service.updateThreadSettings(
					id: threadID,
					settings: ThreadSettingsUpdate(collaborationMode: operation.mode)
				)
				return .composerCommand(.settingsFinished(
					operation,
					.succeeded(())
				))
			default:
				throw AppServerError.protocolError("Unknown composer command effect.")
			}
		}
		catch
		{
			let wasRejected: Bool
			if case AppServerError.requestRejected = error
			{
				wasRejected = true
			}
			else
			{
				wasRejected = false
			}
			let outcomeIsUncertain = mutationSent && !wasRejected

			return failureAction(
				for: effect,
				context: context,
				failure: OperationFailure(
					message: error.localizedDescription,
					outcomeIsUncertain: outcomeIsUncertain
				)
			)
		}
	}
}
