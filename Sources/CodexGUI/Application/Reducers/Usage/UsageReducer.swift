import Foundation

/// Account limits belong to one transport session, independently of source checkout selection.
@MainActor
enum UsageReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	private static let maximumRefreshAttempts = 3

	static func accountSignedOut(_ model: inout WorkspaceModel) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		retire(
			model: &model,
			result: &result
		)
		model.usage = UsageModel()
		return result
	}

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		switch action
		{
		case .usage(let action):
			switch action
			{
			case .refreshRequested(let context):
				request(
					context,
					model: &model,
					result: &result
				)
			case .invalidated(
				let workspace,
				let generation
			):
				guard valid(
					workspace,
					generation: generation,
					model: model
				)
				else
				{
					return result
				}
				invalidate(
					model: &model,
					result: &result
				)
			case .limitsReceived(
				let read,
				let observation
			):
				receiveLimits(
					read,
					observation: observation,
					model: &model,
					result: &result
				)
			case .freshnessDeadlineElapsed(
				let operation,
				let now
			):
				guard valid(
					operation.read.context.workspace,
					generation: operation.read.context.generation,
					model: model
				),
					model.usage.pendingDeadline == operation,
					model.usage.fetchedAt == operation.fetchedAt, now >= operation.deadline
				else
				{
					return result
				}
				model.usage.pendingDeadline = nil
				model.usage.needsRefresh = true
			}
		case .execution(.backendObserved(
			let context,
			.rateLimitsUpdated,
			_
		)):
			guard valid(
				context.workspace,
				generation: context.generation,
				model: model
			)
			else
			{
				return result
			}
			invalidate(
				model: &model,
				result: &result
			)
			request(
				context,
				model: &model,
				result: &result
			)
		case .connection(.connectRequested(let context)):
			guard model.connection.pendingConnection?.requestID == context.requestID,
					context.workspace.sessionID == model.identity.sessionID,
					model.connection.generation == context.generation + 1
			else
			{
				return result
			}
			retire(
				model: &model,
				result: &result
			)
		case .connection(.disconnected(
			let workspace,
			let generation,
			_
		)):
			guard workspace == model.identity, model.connection.generation == generation + 1
			else
			{
				return result
			}
			retire(
				model: &model,
				result: &result
			)
		case .connection(.shutdownRequested):
			retire(
				model: &model,
				result: &result
			)
		default: break
		}
		return result
	}

	private static func receiveLimits(
		_ read: UsageReadOperation,
		observation: OperationResult<UsageObservation>,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			read.context.workspace,
			generation: read.context.generation,
			model: model
		),
			let pending = model.usage.pendingRefresh,
			pending.context == read.context, pending.readsStarted == read.attempt
		else
		{
			return
		}
		switch observation
		{
		case .succeeded(let observation):
			model.usage.snapshot = observation.snapshot
			model.usage.fetchedAt = observation.fetchedAt
			model.usage.freshnessDeadline = observation.freshnessDeadline
			model.usage.error = nil
			model.usage.needsRefresh = false
		case .failed(let failure):
			model.usage.error = "Usage unavailable: \(failure.message)"
			model.usage.needsRefresh = true
		}
		finishRefreshAttempt(
			read,
			model: &model,
			result: &result
		)
	}

	private static func finishRefreshAttempt(
		_ read: UsageReadOperation,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		if model.usage.refreshPending, read.attempt < maximumRefreshAttempts
		{
			model.usage.refreshPending = false
			model.usage.needsRefresh = true
			model.usage.pendingRefresh?.readsStarted += 1
			result.effects.append(.readUsage(UsageReadOperation(
				context: read.context,
				attempt: read.attempt + 1
			)))
		}
		else
		{
			model.usage.pendingRefresh = nil
			if model.usage.refreshPending
			{
				model.usage.needsRefresh = true
				model.usage.error = "Usage changed repeatedly while refreshing. "
					+ "Reconnect to check the latest limits."
			}
			model.usage.refreshPending = false
			if !model.usage.needsRefresh, let fetchedAt = model.usage.fetchedAt,
				let deadline = model.usage.freshnessDeadline
			{
				let operation = UsageDeadlineOperation(
					read: read,
					fetchedAt: fetchedAt,
					deadline: deadline
				)
				model.usage.pendingDeadline = operation
				result.effects.append(.scheduleUsageDeadline(operation))
			}
		}
	}

	private static func valid(
		_ workspace: WorkspaceIdentity,
		generation: Int,
		model: WorkspaceModel
	) -> Bool
	{
		workspace.sessionID == model.identity.sessionID && generation == model.connection.generation
	}

	private static func request(
		_ context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard valid(
			context.workspace,
			generation: context.generation,
			model: model
		),
			model.connection.isConnected
		else
		{
			return
		}
		if model.usage.pendingRefresh != nil
		{
			model.usage.refreshPending = true
			return
		}
		invalidate(
			model: &model,
			result: &result
		)
		model.usage.pendingRefresh = UsageRefreshOperation(
			context: context,
			readsStarted: 1
		)
		model.usage.refreshPending = false
		result.effects.append(.readUsage(UsageReadOperation(
			context: context,
			attempt: 1
		)))
	}

	private static func invalidate(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		model.usage.needsRefresh = true
		if model.usage.pendingRefresh != nil
		{
			model.usage.refreshPending = true
		}
		if let deadline = model.usage.pendingDeadline
		{
			result.effects.append(.cancelUsageDeadline(deadline))
		}
		model.usage.pendingDeadline = nil
	}

	private static func retire(
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		invalidate(
			model: &model,
			result: &result
		)
		if let pending = model.usage.pendingRefresh
		{
			result.effects.append(.cancelUsageRefresh(pending.context))
		}
		model.usage.pendingRefresh = nil
		model.usage.refreshPending = false
	}
}
