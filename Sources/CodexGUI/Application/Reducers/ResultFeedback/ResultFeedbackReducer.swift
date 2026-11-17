import Foundation

@MainActor
enum ResultFeedbackReducer
{
	static let reducer = WorkspaceReducer(reduce: reduce)

	static func reduce(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	) -> WorkspaceReduction
	{
		var reduction = synchronizeOwnership(&model)
		guard case .resultFeedback(let action) = action
		else
		{
			return reduction
		}
		switch action
		{
		case .requested(let operation):
			guard operation.context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			),
				operation.context.threadID == operation.submission.target.threadID,
				operation.context.turnID == operation.submission.target.turnID,
				canSubmit(
					operation.submission.target,
					model: model
				)
			else
			{
				return reduction
			}
			model.resultFeedback.pending = operation
			model.resultFeedback.lastFailure = nil
			reduction.effects.append(.submitResultFeedback(operation))
		case .finished(
			let operation,
			let outcome
		):
			guard operation.context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			),
				model.resultFeedback.pending == operation
			else
			{
				return reduction
			}
			model.resultFeedback.pending = nil
			switch outcome
			{
			case .submitted:
				model.resultFeedback.submitted[operation.submission.target] = operation.submission
					.rating
				model.resultFeedback.lastFailure = nil
			case .failed(
				let failure,
				let unavailable
			):
				model.resultFeedback.lastFailure = failure
				model.resultFeedback.unavailable = unavailable
				if failure
					.outcomeIsUncertain
				{
					model.resultFeedback.uncertain.insert(operation.submission.target)
				}
			}
		}
		return reduction
	}

	static func canSubmit(
		_ target: ResultFeedbackTarget,
		model: WorkspaceModel
	) -> Bool
	{
		guard !model.lifecycle.isShutdown, model.lifecycle.cleanupReservation == nil,
				model.lifecycle.quitReservation == nil, model.connection.isConnected,
				let checkout = model.identity.canonicalCheckoutPath, checkout.hasPrefix("/"),
				!model.conversations.showingArchived,
				model.conversations.selectedConversation == .thread(target.threadID),
				!target.threadID.isEmpty, !target.turnID.isEmpty,
				!model.resultFeedback.unavailable, model.resultFeedback.pending == nil,
				model.resultFeedback.submitted[target] == nil,
				!model.resultFeedback.uncertain.contains(target),
				let content = model.conversations.content[.thread(target.threadID)],
				let turn = content.loadedTurns.first(where:
				{
					$0.id == target.turnID
				}),
				ConversationTurnStatus.isTerminal(turn.status)
		else
		{
			return false
		}
		return turn.items
			.contains
			{
				$0.type == "agentMessage" && $0.text?
					.trimmingCharacters(in: .whitespacesAndNewlines)
					.isEmpty == false
			}
	}

	static func presentation(model: WorkspaceModel) -> ResultFeedbackPresentation
	{
		let targets = model.conversations.content[model.conversations.selectedConversation]?
			.loadedTurns.map
			{
				ResultFeedbackTarget(
					threadID: model.conversations.selectedConversation.threadID ?? "",
					turnID: $0.id
				)
			} ?? []
		return ResultFeedbackPresentation(
			canSubmit: Set(targets.filter
			{
				canSubmit(
					$0,
					model: model
				)
			}),
			pending: model.resultFeedback.pending?.submission.target,
			submitted: model.resultFeedback.submitted,
			uncertain: model.resultFeedback.uncertain
		)
	}

	private static func synchronizeOwnership(_ model: inout WorkspaceModel) -> WorkspaceReduction
	{
		var reduction = WorkspaceReduction()
		let generationChanged = model.resultFeedback.generation != model.connection.generation
		if model.resultFeedback.workspace != model.identity
		{
			if let pending = model.resultFeedback
				.pending
			{
				reduction.effects.append(.cancel(pending.context))
			}
			model.resultFeedback = ResultFeedbackModel(
				workspace: model.identity,
				generation: model.connection.generation
			)
		}
		else if generationChanged || !model.connection.isConnected
		{
			if let pending = model.resultFeedback.pending
			{
				// The server may have accepted the report before transport ownership changed.
				model.resultFeedback.uncertain.insert(pending.submission.target)
				model.resultFeedback.pending = nil
				reduction.effects.append(.cancel(pending.context))
			}
			if generationChanged
			{
				model.resultFeedback.unavailable = false
			}
			model.resultFeedback.generation = model.connection.generation
		}
		return reduction
	}
}
