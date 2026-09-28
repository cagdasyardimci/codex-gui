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
			guard !model.execution.state.isBusy
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
			model.execution.state = .disconnected
			// A viewed-history load does not make a terminal execution owner uncertain.
			let ownerNeedsRecovery = model.execution.hasUncertainRequest
				|| model.execution.commandLifetime.hasPendingCommands
			model.execution.needsReconciliation = ownerNeedsRecovery
				|| model.conversations.selectedConversation.threadID != nil
			if !ownerNeedsRecovery
			{
				model.execution.owner = nil
				model.execution.activeThreadID = nil
				model.execution.activeTurnID = nil
				model.execution.activePlan = nil
				model.execution.activeActivity = nil
				model.execution.outcomeMessage = nil
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
				model.execution.state = model.execution.needsReconciliation ? .disconnected : .ready
				model.execution.statusMessage = model.execution.needsReconciliation
					? "Checking the previous request…" : nil
			case .failed(let failure):
				model.connection.isConnected = false
				model.execution.state = .disconnected
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
			if model.execution.isTaskActive
			{
				model.execution.needsReconciliation = true
				model.execution.hasUncertainRequest = true
			}
			model.connection.generation += 1
			model.connection.pendingConnection = nil
			model.connection.isConnected = false
			model.execution.state = .disconnected
			model.execution.activeTurnID = nil
			model.execution.activePlan = nil
			model.execution.activeActivity = nil
			model.execution.pendingInteractions.removeAll()
			model.execution.statusMessage =
				"\(message) Reopen the conversation to check what finished. "
					+ "Nothing was resent."
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
					!model.execution.isTaskActive
			else
			{
				return result
			}
			model.identity = identity
			// Source transport initialization belongs to the same session even if its first
			// checkout is selected before the finite connection request acknowledges.
			model.execution = ExecutionModel()
			model.execution.state = model.connection.isConnected ? .ready : .disconnected
			model.execution.needsReconciliation = true

			let context = OperationContext(
				workspace: identity,
				generation: model.connection.generation,
				requestID: identity.sessionID
			)
			result.effects = [
				.subscribe(context),
				.restoreExecution(
					context,
					selectedThreadID: selectedThreadID
				)
			]
		case .projectRestored(
			let context,
			let commands,
			let selectedThreadID
		):
			guard context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
			else
			{
				return result
			}
			model.execution.commandLifetime = TaskCommandLifetime(pending: commands)
			model.execution.activeThreadID = commands.first?.threadID

			model.execution.needsReconciliation = selectedThreadID != nil || !commands.isEmpty
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
