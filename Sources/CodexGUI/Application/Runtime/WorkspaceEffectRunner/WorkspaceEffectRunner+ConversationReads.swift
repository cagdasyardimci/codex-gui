import Foundation

extension WorkspaceEffectRunner
{
	/// Change supersession ownership while retaining the producer's one backend fetch.
	func promoteTurnContents(_ promotion: ConversationTurnReadPromotion)
	{
		guard let identity = identity(of: .readTurnContents(promotion.producer))
		else
		{
			return
		}
		let key = EffectKey(
			request: RequestKey(identity.0),
			purpose: identity.1
		)
		guard var pending = tasks[key]
		else
		{
			deliver(.conversations(.turnContentsReceived(
				promotion.producer,
				.failed(OperationFailure(
					message: "The preview fetch ended before this turn could be loaded.",
					outcomeIsUncertain: false
				)),
				observedAt: usageRuntime.now()
			)))
			{
			}
			return
		}
		pending.promotedTurnRead = promotion.consumer
		tasks[key] = pending
		cancelSupersededTurnReads(
			promotion.consumer,
			excluding: key
		)
	}

	func cancelSupersededTurnReads(
		_ incoming: ConversationTurnReadOperation,
		excluding retainedKey: EffectKey? = nil
	)
	{
		let stale = tasks.compactMap
		{
			key, pending -> OperationContext? in
			guard key != retainedKey, case .readTurnContents(let producer) = pending.effect
			else
			{
				return nil
			}
			let old = pending.promotedTurnRead ?? producer
			let sameRole = old.isPreview == incoming.isPreview && old.isWindow == incoming.isWindow
			let foregroundSupersedesWindow = !incoming.isPreview && !incoming.isWindow && old
				.isWindow
			guard old.context.workspace == incoming.context.workspace,
					old.context.generation == incoming.context.generation,
					old.context.requestID != incoming.context.requestID,
					sameRole || foregroundSupersedesWindow
			else
			{
				return nil
			}
			return producer.context
		}
		for context in stale
		{
			cancel(context)
		}
	}

	func preparedTurnPreview(_ turn: CodexTurn) async throws -> ConversationTurnPreview
	{
		let preparer = previewPreparer
		let task = Task.detached(priority: .utility)
		{
			try preparer.prepare(turn)
		}
		return try await withTaskCancellationHandler
		{
			try await task.value
		}
		onCancel:
		{
			task.cancel()
		}
	}
}
