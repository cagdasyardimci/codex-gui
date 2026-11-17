import Foundation

@MainActor
enum ReadAloudReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func canRead(_ model: WorkspaceModel) -> Bool
	{
		!model.lifecycle.isShutdown && model.connection.isConnected && model.readAloud.available
			&& model.conversations.selectedConversation.threadID != nil
			&& model.lifecycle.cleanupReservation == nil && model.lifecycle.quitReservation == nil
	}

	static func presentation(model: WorkspaceModel) -> ReadAloudPresentation
	{
		ReadAloudPresentation(
			canRead: canRead(model),
			activeEntryID: model.readAloud.active?.entryID,
			phase: model.readAloud.phase
		)
	}

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var result = WorkspaceReduction()
		if let active = model.readAloud.active,
			!model.connection.isConnected || model.lifecycle.isShutdown || !valid(
			active.context,
			model
			) || model.conversations.selectedConversation.threadID != active.context.threadID
			|| model.lifecycle.cleanupReservation != nil || model.lifecycle.quitReservation != nil
		{
			model.readAloud.active = nil
			model.readAloud.phase = .idle
			result.effects.append(.cancel(active.context))
		}
		if case .connection(.connectionFinished(
			let context,
			.succeeded
		)) = action,
			valid(
				context,
				model
			), model.connection.isConnected
		{
			model.readAloud.available = false
			model.readAloud.probe = context
			result.effects.append(.readAloud(.probe(context)))
		}
		if !model.connection
			.isConnected
		{
			model.readAloud.available = false; model.readAloud.probe = nil
		}
		guard case .readAloud(let action) = action
		else
		{
			return result
		}
		switch action
		{
		case .requested(let request):
			guard canRead(model), valid(
				request.context,
				model
			),
				request.context.threadID == model.conversations.selectedConversation.threadID,
				isTerminalAgentEntry(
					request.entryID,
					model: model
				),
				(try? ReadAloudTextSegments.make(request.text)) != nil
			else
			{
				return result
			}
			if let active = model.readAloud
				.active
			{
				result.effects.append(.cancel(active.context))
			}
			model.readAloud.active = request
			model.readAloud.phase = .starting
			model.readAloud.lastFailure = nil
			result.effects.append(.readAloud(.play(request)))
		case .stopRequested:
			if let active = model.readAloud
				.active
			{
				result.effects.append(.cancel(active.context))
			}
			model.readAloud.active = nil
			model.readAloud.phase = .idle
		case .availabilityReceived(
			let context,
			let available
		):
			guard valid(
				context,
				model
			), model.readAloud.probe == context
			else
			{
				return result
			}
			model.readAloud.probe = nil
			model.readAloud.available = available
		case .speaking(let request):
			guard model.readAloud.active == request,
					valid(
					request.context,
					model
					)
			else
			{
				return result
			}
			model.readAloud.phase = .speaking
		case .finished(
			let request,
			let failure
		):
			guard model.readAloud.active == request,
					valid(
					request.context,
					model
					)
			else
			{
				return result
			}
			model.readAloud.active = nil
			model.readAloud.phase = .idle
			model.readAloud.lastFailure = failure
			if failure != nil
			{
				model.readAloud.available = false
			}
		}
		return result
	}

	private static func isTerminalAgentEntry(
		_ entryID: String,
		model: WorkspaceModel
	) -> Bool
	{
		guard let identity = ConversationEntryIdentity(entryID),
				!identity.turnID.isEmpty, !identity.itemID.isEmpty,
				let content = model.conversations.content[model.conversations.selectedConversation],
				let turn = content.loadedTurns.first(where:
				{
					$0.id == identity.turnID
				}),
				ConversationTurnStatus.isTerminal(turn.status)
		else
		{
			return false
		}
		return turn.items
			.contains
			{
				$0.id == identity.itemID && $0.type == "agentMessage" && $0.text?
					.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
			}
	}

	private static func valid(
		_ context: OperationContext,
		_ model: WorkspaceModel
	) -> Bool
	{
		context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		)
	}
}
