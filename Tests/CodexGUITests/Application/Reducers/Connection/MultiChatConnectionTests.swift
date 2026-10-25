import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Multi-chat connection lifecycle"
)
struct MultiChatConnectionTests
{
	@Test func disconnectionPreservesEveryRemoteOwnerAndCommandBarrier()
	{
		var model = makeModel()
		model.conversations.selectedConversation = .thread("idle")
		for threadID in ["alpha", "beta"]
		{
			var execution = ExecutionModel()
			execution.state = .running
			execution.activeThreadID = threadID
			execution.activeTurnID = "turn-" + threadID
			execution.owner = ExecutionOwner(submission: context(
				model,
				threadID: threadID
			))
			execution.commandLifetime = TaskCommandLifetime(pending: [TaskCommandOwnership(
				threadID: threadID,
				turnID: "turn-" + threadID,
				itemID: "command-" + threadID
			)])
			model.executions.entries[.thread(threadID)] = execution
		}
		_ = ConnectionReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: model.connection.generation,
				message: "Transport lost."
			))
		)
		#expect(!model.connection.isConnected)
		#expect(model.connection.generation == 2)
		#expect(model.execution.state == .disconnected)
		for threadID in ["alpha", "beta"]
		{
			let execution = model.execution(for: .thread(threadID))
			#expect(execution.state == .disconnected)
			#expect(execution.needsReconciliation)
			#expect(execution.hasUncertainRequest)
			#expect(execution.activeThreadID == threadID)
			#expect(execution.activeTurnID == nil)
			#expect(execution.owner?.submission.threadID == threadID)
			#expect(execution.commandLifetime.pending.count == 1)
		}
		#expect(model.hasActiveExecution)
		#expect(WorkspaceLifecycleReducer.blocksCleanup(model))
	}

	@Test func activeStatusRecoversKnownUnloadedThreadWithoutChangingSelection() throws
	{
		var model = makeModel()
		model.conversations.threads = [try #require(ThreadSummary(json: [
			"id": "background",
			"cwd": "/checkout",
		]))]
		let status = try #require(ThreadStatus(json: ["type": "active", "activeFlags": []]))
		let result = WorkspaceLifecycleComposition.reduceDomainEvent(
			&model,
			.backendObserved(
				.threadStatusChanged(
					threadId: "background",
					status: status
				),
				observedAt: .distantPast
			),
			context: context(model)
		)
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.execution(for: .thread("background")).activeThreadID == "background")
		#expect(model.execution(for: .thread("background")).needsReconciliation)
		#expect(result.effects.contains
		{
			if case .readConversationHistory(let operation) = $0
			{
				return operation.context.threadID == "background" && operation.purpose == .recovery
			}
			return false
		})
	}

	@Test func foreignActiveStatusDoesNotCreateExecutionOwner() throws
	{
		var model = makeModel()
		// A foreign summary never enters the runtime-validated checkout list.
		model.conversations.threads = []
		let status = try #require(ThreadStatus(json: ["type": "active", "activeFlags": []]))
		_ = WorkspaceLifecycleComposition.reduceDomainEvent(
			&model,
			.backendObserved(
				.threadStatusChanged(
					threadId: "foreign",
					status: status
				),
				observedAt: .distantPast
			),
			context: context(model)
		)
		#expect(model.executions.entries[.thread("foreign")] == nil)
		#expect(!model.hasActiveExecution)
		#expect(model.conversations.pendingList != nil)
	}

	@Test func unrelatedBusyConversationRefusesReconnectAndProjectReplacement()
	{
		var model = makeModel()
		model.conversations.selectedConversation = .thread("idle")
		var running = ExecutionModel()
		running.state = .running
		running.activeThreadID = "background"
		model.executions.entries[.thread("background")] = running
		let original = model.identity
		let reconnect = ConnectionReducer.reduce(
			&model,
			.connection(.connectRequested(context(model)))
		)
		#expect(reconnect.effects.isEmpty)
		#expect(model.connection.generation == 1)
		let replacement = WorkspaceIdentity(
			sessionID: original.sessionID,
			canonicalCheckoutPath: "/another-checkout"
		)
		let opened = ConnectionReducer.reduce(
			&model,
			.connection(.projectOpened(
				replacement,
				selectedThreadID: nil
			))
		)
		#expect(opened.effects.isEmpty)
		#expect(model.identity == original)
		#expect(!WorkspaceLifecycleReducer.accepts(
			.workspaceLifecycle(.projectOpeningRequested(
				context(model),
				URL(fileURLWithPath: "/new")
			)),
			model: model
		))
	}

	@Test func idleProjectReplacementLeavesNoAnonymousRecoveryBarrier()
	{
		var model = makeModel()
		model.conversations.selectedConversation = .thread("previous")
		var previous = ExecutionModel()
		previous.state = .completed
		previous.activeThreadID = "previous"
		model.executions.entries[.thread("previous")] = previous
		let replacement = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: "/replacement"
		)
		_ = ConnectionReducer.reduce(
			&model,
			.connection(.projectOpened(
				replacement,
				selectedThreadID: nil
			))
		)
		#expect(model.identity == replacement)
		#expect(model.executions.entries.isEmpty)
		#expect(!model.blocksExecutionCleanup)
		_ = ConnectionReducer.reduce(
			&model,
			.connection(.projectRestored(
				context(model),
				pendingCommands: [],
				selectedThreadID: "saved"
			))
		)
		#expect(Set(model.executions.entries.keys) == Set([.thread("saved")]))
		#expect(model.execution(for: .thread("saved")).needsReconciliation)
	}

	private func makeModel() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/checkout"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		threadID: String? = nil
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: threadID
		)
	}
}
