import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ExecutionRecoveryTokenTests
{
	@Test func newerCommandInvalidatesTokenAndAcceptedHistoryMintsAfterItsOwnEvidence()
	{
		var (model, context) = fixture()
		let original = ReconciliationOperation(
			context: context,
			commandRevision: 0
		)
		_ = observeHistory(
			original,
			detail: detail(),
			model: &model
		)
		#expect(model.execution.lastReconciledRequestID == context.requestID)
		let command = command()
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.itemStarted(
					threadId: "owner",
					turnId: "live",
					item: command
				)
			))
		)
		#expect(model.execution.lastReconciledRequestID == nil)

		let fresh = ReconciliationOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "owner"
			),
			commandRevision: 1
		)
		_ = observeHistory(
			fresh,
			detail: detail(commands: [command]),
			model: &model
		)
		#expect(model.execution.commandEventRevisions["owner"] == 2)
		#expect(model.execution.lastReconciledRequestID == fresh.context.requestID)

		_ = observeHistory(
			original,
			detail: detail(),
			model: &model
		)
		#expect(model.execution.lastReconciledRequestID == fresh.context.requestID)
		_ = observeHistory(
			fresh,
			detail: detail(threadID: "foreign"),
			model: &model
		)
		#expect(model.execution.lastReconciledRequestID == fresh.context.requestID)
		let staleContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation - 1,
			requestID: fresh.context.requestID,
			threadID: "owner"
		)
		_ = observeHistory(
			ReconciliationOperation(
				context: staleContext,
				commandRevision: 2
			),
			detail: detail(),
			model: &model
		)
		#expect(model.execution.lastReconciledRequestID == fresh.context.requestID)
	}

	@Test func anotherThreadsCommandEvidenceCannotRevokeAcceptedOwnerToken()
	{
		var (model, context) = fixture()
		_ = observeHistory(
			ReconciliationOperation(
				context: context,
				commandRevision: 0
			),
			detail: detail(),
			model: &model
		)
		ExecutionReducer.recordCommandObservation(
			threadID: "other",
			turns: detail(
				threadID: "other",
				commands: [command()]
			).turns,
			model: &model
		)
		#expect(model.execution.lastReconciledRequestID == context.requestID)
		#expect(model.execution(for: .thread("other")).commandEventRevisions["other"] == 1)
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/recovery-token"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("owner")
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "owner",
			turnID: "live"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.activeThreadID = "owner"
		model.execution.activeTurnID = "live"
		model.execution.state = .running
		return (model, context)
	}

	private func observeHistory(
		_ operation: ReconciliationOperation,
		detail: ThreadDetail,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				operation,
				detail
			))
		)
	}

	private func detail(
		threadID: String = "owner",
		commands: [CodexItem] = []
	) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: [
				"id": threadID,
				"status": ["type": "active"]
			])!,
			turns: [CodexTurn(
				id: "live",
				status: "inProgress",
				items: commands,
				error: nil
			)],
			nextTurnsCursor: nil
		)
	}

	private func command() -> CodexItem
	{
		CodexItem(json: [
			"id": "command",
			"type": "commandExecution",
			"status": "inProgress"
		])!
	}
}
