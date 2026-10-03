import Foundation

/// Git captures bind only to an acknowledged submission, never to selected or replayed turns.
@MainActor
enum GitTurnBaselineLifecycle
{
	static func acknowledge(
		_ acknowledgement: SubmissionAcknowledgement,
		context: OperationContext,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		let threadID = acknowledgement.thread.id
		guard !model.execution.hasUncertainRequest,
				model.execution.activeThreadID == threadID
		else
		{
			return
		}
		model.execution.gitTurnBaselineRevisions[threadID, default: 0] += 1
		if case .unavailable(let failure)? = acknowledgement.gitTurnBaselineResult
		{
			model.execution.gitTurnBaselineBindings[threadID] = GitTurnBaselineBindingStatus(
				context: context,
				turnID: acknowledgement.turn.id,
				result: .unavailable(failure)
			)
			return
		}
		let capturedReference: GitTurnBaselineReference?
		if case .captured(let reference)? = acknowledgement.gitTurnBaselineResult
		{
			capturedReference = reference
		}
		else
		{
			capturedReference = acknowledgement.gitTurnBaseline
		}
		guard let reference = capturedReference,
				matches(
				reference,
				context: context,
				threadID: threadID
				)
		else
		{
			model.execution.gitTurnBaselineBindings.removeValue(forKey: threadID)
			return
		}
		model.execution.gitTurnBaselineBindings[threadID] = GitTurnBaselineBindingStatus(
			context: context,
			turnID: acknowledgement.turn.id,
			result: nil
		)
		result.effects.append(.bindGitTurnBaseline(GitTurnBaselineBindingOperation(
			context: context,
			reference: reference,
			turnID: acknowledgement.turn.id
		)))
	}

	static func finishBinding(
		_ observation: GitTurnBaselineResult,
		context: OperationContext,
		threadID: String,
		turnID: String,
		model: inout WorkspaceModel
	)
	{
		guard context.belongsTo(
			workspace: model.identity,
			generation: model.connection.generation
		), var status = model.execution.gitTurnBaselineBindings[threadID],
		status.context.isSameRequest(as: context), status.turnID == turnID,
		status.result == nil
		else
		{
			return
		}
		if case .captured(let reference) = observation
		{
			guard matches(
				reference,
				context: context,
				threadID: threadID
			),
				reference.acceptedTurnID == turnID
			else
			{
				return
			}
		}
		status.result = observation
		model.execution.gitTurnBaselineBindings[threadID] = status
		model.execution.gitTurnBaselineRevisions[threadID, default: 0] += 1
	}

	/// A timed-out start can own a capture, but history must identify one new turn before binding.
	static func resolvePendingCapture(
		_ detail: ThreadDetail,
		model: inout WorkspaceModel,
		result: inout WorkspaceReduction
	)
	{
		guard model.execution.hasUncertainRequest, model.execution.needsReconciliation,
				let pending = model.execution.pendingGitTurnBaselineCapture,
				model.execution.activeThreadID == detail.summary.id,
				pending.reference.identity.threadID == detail.summary.id
		else
		{
			return
		}
		let knownTurnIsVisible = pending.previousTurnIDs.isEmpty || detail.turns.contains
		{
			pending.previousTurnIDs.contains($0.id)
		}
		guard knownTurnIsVisible || detail.nextTurnsCursor == nil
		else
		{
			return
		}
		let newTurns = detail.turns.filter
		{
			!pending.previousTurnIDs.contains($0.id)
		}
		model.execution.pendingGitTurnBaselineCapture = nil
		guard newTurns.count == 1,
				pending.context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
				)
		else
		{
			result.effects.append(.discardGitTurnBaseline(GitTurnBaselineDiscardOperation(
				context: pending.context,
				reference: pending.reference
			)))
			return
		}
		let turnID = newTurns[0].id
		model.execution.gitTurnBaselineBindings[detail.summary.id] = GitTurnBaselineBindingStatus(
			context: pending.context,
			turnID: turnID,
			result: nil
		)
		model.execution.gitTurnBaselineRevisions[detail.summary.id, default: 0] += 1
		result.effects.append(.bindGitTurnBaseline(GitTurnBaselineBindingOperation(
			context: pending.context,
			reference: pending.reference,
			turnID: turnID
		)))
	}

	private static func matches(
		_ reference: GitTurnBaselineReference,
		context: OperationContext,
		threadID: String
	) -> Bool
	{
		let identity = reference.identity
		return identity.workspaceSessionID == context.workspace.sessionID
			&& identity.repositoryRoot == context.workspace.canonicalCheckoutPath
			&& identity.executionGeneration == context.generation
			&& identity.submissionRequestID == context.requestID
			&& identity.threadID == threadID
	}
}
