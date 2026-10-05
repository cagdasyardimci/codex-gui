import Foundation

/// Transport facts and session invalidation are reduced independently of remote execution.
@MainActor
enum ConnectionReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		guard case .connection(let action) = action
		else
		{
			return WorkspaceReduction()
		}
		var result = WorkspaceReduction()
		switch action
		{
		case .connectRequested(var context):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			guard !model.allExecutions.contains(where:
				{
					$0.state.isBusy
				})
			else
			{
				model.connection.statusMessage = "Stop the current task before reconnecting."
				return result
			}
			model.connection.generation += 1
			context = OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: context.requestID
			)
			model.connection.pendingConnection = context
			model.connection.isConnected = false
			model.connection.statusMessage = "Connecting to Codex…"
			model.updateAllExecutions
			{
				execution in
				execution.pendingResponses.removeAll()
				execution.pendingReconciliation = nil
				execution.state = .disconnected
				// Recovery preserves each remote owner, independently of displayed history.
				let ownerNeedsRecovery = execution.hasUncertainRequest
					|| execution.commandLifetime.hasPendingCommands
					|| (execution.needsReconciliation && execution.activeThreadID != nil)
				execution.needsReconciliation = ownerNeedsRecovery
				if !ownerNeedsRecovery
				{
					execution.owner = nil
					execution.activeThreadID = nil
					execution.activeTurnID = nil
					execution.activePlan = nil
					execution.activeActivity = nil
					execution.outcomeMessage = nil
				}
			}
			if let selectedThreadID = model.conversations.selectedConversation.threadID
			{
				var execution = model.execution(for: .thread(selectedThreadID))
				execution.needsReconciliation = true
				model.executions.entries[.thread(selectedThreadID)] = execution
			}
			result.effects = [.subscribe(context), .readExecutableVersion(context)]
			result.domainEvents = [.connectionBegan]
		case .executableVersionReceived(
			let context,
			let observation
		):
			guard context == model.connection.pendingConnection
			else
			{
				return result
			}
			switch observation
			{
			case .succeeded(let version):
				model.connection.backendDescription = version == "codex-cli 0.153.2"
					? "\(version) · Tested baseline" : "\(version) · Compatibility unverified"
				result.effects = [.connect(context)]
			case .failed(let failure):
				model.connection.pendingConnection = nil
				model.connection.statusMessage = failure.message
			}
		case .connectionFinished(
			let context,
			let observation
		):
			guard context == model.connection.pendingConnection
			else
			{
				return result
			}
			model.connection.pendingConnection = nil
			switch observation
			{
			case .succeeded:
				model.connection.isConnected = true
				model.connection.statusMessage = nil
				model.updateAllExecutions
				{
					execution in
					execution.state = execution.needsReconciliation ? .disconnected : .ready
					execution.statusMessage = execution.needsReconciliation
						? "Checking the previous request…" : nil
				}
			case .failed(let failure):
				model.connection.isConnected = false
				model.updateAllExecutions
				{
					$0.state = .disconnected
				}
				model.connection.statusMessage = failure.message
			}
		case .disconnected(
			let workspace,
			let generation,
			let message
		):
			guard workspace == model.identity, generation == model.connection.generation
			else
			{
				return result
			}
			model.updateAllExecutions
			{
				execution in
				if execution.isTaskActive
				{
					execution.needsReconciliation = true
					execution.hasUncertainRequest = true
				}
				execution.state = .disconnected
				execution.activeTurnID = nil
				execution.activePlan = nil
				execution.activeActivity = nil
				execution.pendingInteractions.removeAll()
				execution.pendingResponses.removeAll()
				execution.pendingReconciliation = nil
				execution.statusMessage =
					"\(message) Reopen the conversation to check what finished. "
						+ "Nothing was resent."
			}
			model.connection.generation += 1
			model.connection.pendingConnection = nil
			model.connection.isConnected = false
			result.domainEvents = [.connectionDisconnected]
			result.presentationCommands = [.taskFinished]
			result.effects = [.subscribe(OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: workspace.sessionID
			))]
		case .projectOpened(
			let identity,
			let selectedThreadID
		):
			guard identity.sessionID == model.identity.sessionID,
					!model.hasActiveExecution
			else
			{
				return result
			}
			let pendingCaptures = model.allExecutions.compactMap(\.pendingGitTurnBaselineCapture)
			model.identity = identity
			// Source transport initialization belongs to the same session even if its first
			// checkout is selected before the finite connection request acknowledges.
			model.executions = ExecutionRegistry()
			if let selectedThreadID
			{
				var execution = ExecutionModel()
				execution.state = model.connection.isConnected ? .ready : .disconnected
				execution.needsReconciliation = true
				model.executions.entries[.thread(selectedThreadID)] = execution
			}

			let context = OperationContext(
				workspace: identity,
				generation: model.connection.generation,
				requestID: identity.sessionID
			)
			for pendingCapture in pendingCaptures
			{
				result.effects.append(.discardGitTurnBaseline(GitTurnBaselineDiscardOperation(
					context: context,
					reference: pendingCapture.reference
				)))
			}
			result.effects += [
				.subscribe(context),
				.restoreExecution(
					context,
					selectedThreadID: selectedThreadID
				)
			]
		case .projectRestored(
			let context,
			let commands,
			let selectedThreadID,
			let pendingExecutions
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			for threadID in Set(pendingExecutions) where !threadID.isEmpty
			{
				var execution = model.execution(for: .thread(threadID))
				execution.activeThreadID = threadID
				execution.needsReconciliation = true
				execution.hasUncertainRequest = true
				model.executions.entries[.thread(threadID)] = execution
			}
			let commandsByThread = Dictionary(
				grouping: commands,
				by: \.threadID
			)
			for (threadID, pending) in commandsByThread
			{
				var execution = model.execution(for: .thread(threadID))
				execution.commandLifetime = TaskCommandLifetime(pending: pending)
				execution.activeThreadID = threadID
				execution.needsReconciliation = true
				model.executions.entries[.thread(threadID)] = execution
			}
			if let selectedThreadID
			{
				var execution = model.execution(for: .thread(selectedThreadID))
				execution.needsReconciliation = true
				model.executions.entries[.thread(selectedThreadID)] = execution
			}
			result.domainEvents = [.projectRestored]
		case .shutdownRequested:
			model.connection.generation += 1
			model.connection.pendingConnection = nil
			model.connection.isConnected = false
			result.effects = [.detachSubscription, .disconnect]
		}
		return result
	}
}
