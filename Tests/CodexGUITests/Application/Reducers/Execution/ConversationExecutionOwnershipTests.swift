import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationExecutionOwnershipTests
{
	@Test func lateAnonymousPreparationAdoptsOnlyCapturedDraftLifetime()
	{
		var (model, submission) = fixture()
		model.composer.drafts[.newChat] = ComposerDraft(lifetime: 1)
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)

		#expect(result.effects.contains
		{
			if case .persistExecutionRecovery(
				_,
				let threadIDs
			) = $0
			{
				return threadIDs == ["prepared"]
			}
			return false
		})
		#expect(model.execution.owner == nil)
		#expect(model.execution.state == .ready)
		#expect(model.executions.entries[.newChat(lifetime: 0)] == nil)
		#expect(model.execution(for: .thread("prepared")).owner?.submission.requestID
			== submission.context.requestID)
		#expect(model.execution(for: .thread("prepared")).activeThreadID == "prepared")
		#expect(model.composer.drafts[.newChat]?.lifetime == 1)
	}

	@Test func anonymousStopUsesCapturedOwnerAfterRepeatedNewChat()
	{
		var (model, submission) = fixture()
		model.composer.drafts[.newChat] = ComposerDraft(lifetime: 1)
		let stopContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.stopRequested(
				stopContext,
				ownerRequestID: submission.context.requestID
			))
		)

		#expect(model.execution.stopRequested == false)
		#expect(model.executions.entries[.newChat(lifetime: 0)]?.stopRequested == true)
		#expect(model.executions.entries[.newChat(lifetime: 0)]?.stopContext == stopContext)
		#expect(stopContext.requestID != submission.context.requestID)
	}

	@Test func unknownAnonymousStopCannotCancelSelectedExecution()
	{
		var (model, _) = fixture()
		let unknown = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.stopRequested(unknown))
		)

		#expect(model.execution.state == .running)
		#expect(model.execution.stopRequested == false)
		#expect(result.effects.isEmpty)
	}

	@Test func wrongTurnErrorDoesNotRewriteOwnerStatus()
	{
		var (model, submission) = fixture()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)
		model.conversations.selectedConversation = .thread("prepared")
		model.execution.activeTurnID = "actual"
		model.execution.statusMessage = "Keep this"
		model.conversations.selectedConversation = .thread("other")
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				submission.context,
				.error(
					threadId: "prepared",
					turnId: "wrong",
					message: "Must reject",
					willRetry: false
				)
			))
		)

		#expect(result.domainEvents.isEmpty)
		#expect(model.execution(for: .thread("prepared")).statusMessage == "Keep this")
		#expect(model.execution.statusMessage == nil)
	}

	@Test func recoveredRunningTurnUsesCurrentTransportWithoutResendingSubmission()
	{
		var (model, submission) = fixture()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)
		model.conversations.selectedConversation = .thread("prepared")
		model.execution.state = .disconnected
		model.execution.needsReconciliation = true
		model.execution.hasUncertainRequest = true
		model.connection.generation += 1
		let recovery = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "prepared"
		)
		let detail = ThreadDetail(
			summary: ThreadSummary(json: [
				"id": "prepared",
				"status": ["type": "active"]
			])!,
			turns: [CodexTurn(
				id: "recovered-turn",
				status: "inProgress",
				items: [],
				error: nil
			)],
			nextTurnsCursor: nil
		)
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				ReconciliationOperation(
					context: recovery,
					commandRevision: 0
				),
				detail
			))
		)

		#expect(model.execution.owner?.submission.generation == model.connection.generation)
		#expect(model.execution.owner?.submission.requestID == recovery.requestID)
		#expect(model.execution.submissionRequest?.requestID == submission.context.requestID)
		#expect(model.execution.state == .running)
		#expect(WorkspaceEligibility(model: model).canSteer)
		#expect(result.effects.allSatisfy
		{
			if case .startSubmission = $0
			{
				return false
			}
			return true
		})

		let stopContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "prepared",
			turnID: "recovered-turn"
		)
		let stopped = ExecutionReducer.reduce(
			&model,
			.execution(.stopRequested(
				stopContext,
				ownerRequestID: recovery.requestID
			))
		)
		#expect(model.execution.pendingInterruption?.context == stopContext)
		#expect(stopped.effects.contains
		{
			if case .interrupt(let operation) = $0
			{
				return operation.context == stopContext
			}
			return false
		})
	}

	@Test func foreignHistoryCannotRetargetCapturedExecution()
	{
		var (model, submission) = fixture()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "prepared"
		)
		let operation = ReconciliationOperation(
			context: context,
			commandRevision: 0
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.reconciliationRequested(operation))
		)
		let foreign = ThreadDetail(
			summary: ThreadSummary(json: ["id": "foreign"])!,
			turns: [],
			nextTurnsCursor: nil
		)
		let reconciled = ExecutionReducer.reduce(
			&model,
			.execution(.reconciliationFinished(
				context,
				.succeeded(foreign)
			))
		)
		let completed = ExecutionReducer.reduce(
			&model,
			.execution(.completedHistoryReceived(
				operation,
				.succeeded(foreign)
			))
		)

		#expect(reconciled.domainEvents.isEmpty)
		#expect(completed.domainEvents.isEmpty)
		#expect(model.execution(for: .thread("prepared")).activeThreadID == "prepared")
		#expect(model.execution(for: .thread("prepared")).state == .running)
		#expect(model.executions.entries[.thread("foreign")] == nil)
	}

	@Test func terminalStartReplayRejectsWhileDistinctRemoteTurnKeepsOwnCurrentOwner()
	{
		var (model, submission) = fixture()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)
		model.conversations.selectedConversation = .thread("prepared")
		model.execution.owner?.submission.turnID = "terminal"
		model.execution.agentOutcome = .completed
		model.execution.state = .completed
		model.execution.submissionRequest = nil
		model.conversations.selectedConversation = .thread("other")
		let observation = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		for turnID in ["terminal", "remote", "foreign-live"]
		{
			let result = ExecutionReducer.reduce(
				&model,
				.execution(.backendObserved(
					observation,
					.turnStarted(
						threadId: "prepared",
						turn: CodexTurn(
							id: turnID,
							status: "inProgress",
							items: [],
							error: nil
						)
					)
				))
			)
			if turnID == "terminal"
			{
				#expect(result.domainEvents.isEmpty)
				#expect(model.execution(for: .thread("prepared")).state == .completed)
			}
			else
			{
				#expect(model.execution(for: .thread("prepared")).activeTurnID == "remote")
				#expect(model.execution(for: .thread("prepared")).agentOutcome == nil)
				#expect(model.execution(for: .thread("prepared")).owner?.submission.requestID
					== observation.requestID)
			}
		}
		#expect(model.execution.owner == nil)
	}

	@Test func recoveredLiveTurnCanStopWhileCommandBarrierWaitsForSeparateExit() throws
	{
		var (model, submission) = fixture()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared(submission))
			))
		)
		model.conversations.selectedConversation = .thread("prepared")
		model.execution.state = .disconnected
		model.execution.needsReconciliation = true
		model.execution.hasUncertainRequest = true
		model.execution.commandLifetime = TaskCommandLifetime(pending: [TaskCommandOwnership(
			threadID: "prepared",
			turnID: "live",
			itemID: "command"
		)])
		model.connection.generation += 1
		let recovery = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "prepared"
		)
		let live = CodexTurn(
			id: "live",
			status: "inProgress",
			items: [],
			error: nil
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				ReconciliationOperation(
					context: recovery,
					commandRevision: 0
				),
				ThreadDetail(
					summary: ThreadSummary(json: [
						"id": "prepared",
						"status": ["type": "active"]
					])!,
					turns: [live],
					nextTurnsCursor: nil
				)
			))
		)
		#expect(model.execution.state == .running)
		#expect(model.execution.commandLifetime.hasPendingCommands)
		#expect(model.blocksExecutionCleanup)

		let stop = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "prepared",
			turnID: "live"
		)
		let stopped = ExecutionReducer.reduce(
			&model,
			.execution(.stopRequested(
				stop,
				ownerRequestID: recovery.requestID
			))
		)
		#expect(stopped.effects.filter
		{
			if case .interrupt = $0
			{
				return true
			}
			return false
		}.count == 1)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				recovery,
				.turnCompleted(
					threadId: "prepared",
					turn: CodexTurn(
						id: "live",
						status: "interrupted",
						items: [],
						error: nil
					)
				)
			))
		)
		#expect(model.blocksExecutionCleanup)
		#expect(model.executionRecoveryThreadIDs == ["prepared"])
		let exited = try #require(CodexItem(json: [
			"id": "command",
			"type": "commandExecution",
			"status": "completed"
		]))
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				recovery,
				.itemCompleted(
					threadId: "prepared",
					turnId: "live",
					item: exited
				)
			))
		)
		#expect(model.execution.state == .stopped)
		#expect(!model.blocksExecutionCleanup)
		#expect(model.executionRecoveryThreadIDs.isEmpty)
	}

	private func fixture() -> (WorkspaceModel, ComposerSubmission)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/execution-ownership"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let draft = ComposerDraft(text: "Captured input")
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.composer.drafts[.newChat] = draft
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.submissionRequest = context
		model.execution.state = .running
		return (model, submission)
	}

	private func prepared(_ submission: ComposerSubmission) -> PreparedSubmission
	{
		PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: ThreadSummary(json: ["id": "prepared"])!,
				turns: [],
				nextTurnsCursor: nil
			)
		)
	}
}
