import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConversationExecutionRegistryTests
{
	@Test func selectedProjectionDoesNotTransferBackgroundExecution()
	{
		var model = fixture()
		model.execution.state = .running
		model.execution.activeThreadID = "a"
		model.execution.activeTurnID = "turn-a"
		model.execution.statusMessage = "Working in A"
		model.conversations.selectedConversation = .thread("b")

		#expect(model.execution.state == .ready)
		#expect(model.execution.activeThreadID == nil)
		#expect(model.execution(for: .thread("a")).activeTurnID == "turn-a")
		#expect(model.hasActiveExecution)
		#expect(WorkspaceEligibility(model: model).canSend)

		model.execution.state = .running
		model.execution.activeThreadID = "b"
		model.execution.activeTurnID = "turn-b"
		#expect(!WorkspaceEligibility(model: model).canSend)
		#expect(model.execution(for: .thread("a")).statusMessage == "Working in A")
	}

	@Test func requestScopeRestoresSelectedProjectionBeforeReturning()
	{
		var model = fixture()
		let context = context(
			model,
			threadID: "a"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.conversations.selectedConversation = .thread("b")
		let action = WorkspaceAction.execution(.activityReceived(
			context,
			"Work"
		))
		_ = WorkspaceExecutionScope.reduce(
			action: action,
			model: &model,
			body:
			{
				model in
				#expect(model.execution.owner?.submission == context)
				model.execution.statusMessage = "Owner A"
				return WorkspaceReduction()
			}
		)

		#expect(model.conversations.selectedConversation == .thread("b"))
		#expect(model.execution.statusMessage == nil)
		#expect(model.execution(for: .thread("a")).statusMessage == "Owner A")
	}

	@Test func recoveryRequestIDsRequireThreadWhenSharedAcrossOwners()
	{
		var model = fixture()
		let requestID = UUID()
		for threadID in ["a", "b"]
		{
			var value = ExecutionModel()
			value.pendingReconciliation = ReconciliationOperation(
				context: context(
					model,
					requestID: requestID,
					threadID: threadID
				),
				commandRevision: 0
			)
			model.executions.entries[.thread(threadID)] = value
		}

		let anonymous = context(
			model,
			requestID: requestID,
			threadID: nil
		)
		#expect(model.executions.identity(for: anonymous) == nil)
		var explicit = anonymous
		explicit.threadID = "b"
		#expect(model.executions.identity(for: explicit) == .thread("b"))
	}

	@Test func staleRequestReadRejectsWhileDurableScopeRetainsOriginalOwner()
	{
		var model = fixture()
		let captured = context(
			model,
			threadID: "a"
		)
		model.execution.owner = ExecutionOwner(submission: captured)
		model.connection.generation += 1
		model.conversations.selectedConversation = .thread("b")
		#expect(model.execution(for: captured) == nil)

		_ = WorkspaceExecutionScope.reduce(
			action: .execution(.draftAcknowledgementFinished(
				captured,
				.failed(OperationFailure(
					message: "Synthetic persistence result",
					outcomeIsUncertain: false
				))
			)),
			model: &model,
			body:
			{
				model in
				#expect(model.execution.owner?.submission == captured)
				return WorkspaceReduction()
			}
		)
		#expect(model.execution.owner == nil)
	}

	@Test func commandBarrierProtectsOwningThreadAndAggregatesDeterministically()
	{
		var model = fixture()
		model.execution.commandLifetime = TaskCommandLifetime(pending: [TaskCommandOwnership(
			threadID: "a",
			turnID: "turn-a",
			itemID: "command-a"
		)])
		model.conversations.selectedConversation = .thread("b")
		model.conversations.threads = [ThreadSummary(json: ["id": "a"])!]
		#expect(WorkspaceEligibility(model: model).canSend)
		#expect(model.blocksExecutionCleanup)
		#expect(!WorkspaceEligibility(model: model).acceptsManagement(.delete(context(
			model,
			threadID: "a"
		))))
		#expect(model.pendingCommandOwnership.map(\.threadID) == ["a"])
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/execution-registry"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("a")
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		requestID: UUID = UUID(),
		threadID: String?
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: requestID,
			threadID: threadID
		)
	}
}
