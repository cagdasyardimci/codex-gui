import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct WorkspaceFeatureCompositionTests
{
	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/composition"
		))
		model.connection.generation = 1
		model.connection.isConnected = true
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread("thread")
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
	}

	private func detail(status: String) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: [
				"id": "thread",
				"cwd": "/tmp/composition"
			])!,
			turns: [CodexTurn(
				id: "turn",
				status: status,
				items: [],
				error: nil
			)],
			nextTurnsCursor: nil
		)
	}

	@Test func selectionClearsDisplayedConversationWithoutRevokingRunningOwner()
	{
		var model = fixture()
		var owner = context(model)
		owner.turnID = "turn"
		model.execution.owner = ExecutionOwner(submission: owner)
		model.execution.activeThreadID = "thread"
		model.execution.activeTurnID = "turn"
		model.execution.state = .running
		let captured = context(model)
		let result = WorkspaceFeatureComposition.reduce(
			&model,
			.conversations(.newChatOpened(captured))
		)
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.execution.owner?.submission == owner)
		#expect(model.execution.activeThreadID == "thread")
		#expect(model.execution.activeTurnID == "turn")
		#expect(model.execution.state == .running)
		#expect(result.domainEvents.contains
		{
			if case .conversationSelectionChanged(nil) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func recoveryAndCompletionReadsAreRequestedInTheSameReduction()
	{
		for completed in [false, true]
		{
			var model = fixture()
			let captured = context(model)
			let operation = ReconciliationOperation(
				context: captured,
				commandRevision: 0
			)
			let action: WorkspaceAction = completed
				? .execution(.completedHistoryRequested(operation))
				: .execution(.reconciliationRequested(operation))
			let result = WorkspaceFeatureComposition.reduce(
				&model,
				action
			)
			let pending = model.conversations.pendingReads[ConversationReadKey(
				purpose: completed ? .completion : .recovery,
				threadID: "thread"
			)]
			#expect(pending?.context == captured)
			#expect(result.effects.contains
			{
				if case .readConversationHistory = $0
				{
					return true
				}
				return false
			})
			#expect(model.execution.pendingReconciliation == (completed ? nil : operation))
		}
	}

	@Test func selectionPlacesExecutionOutputsBeforePersistenceAndHistory()
	{
		var model = fixture()
		model.conversations.selectedConversation = .newChat
		let captured = context(model)
		let result = WorkspaceFeatureComposition.reduceConversation(
			&model,
			.conversations(.selectionRequested(captured)),
			reduceSelectionExecution:
			{
				_, _ in WorkspaceReduction(
					effects: [.persistCommands(
						captured,
						[]
					)],
					domainEvents: [.conversationContentChanged],
					presentationCommands: [.taskFinished]
				)
			}
		)
		#expect(result.effects.count == 3)
		if case .persistCommands = result.effects[0]
		{
		}
		else
		{
			Issue.record("Execution effect must precede selection persistence")
		}
		if case .persistConversationSelection = result.effects[1]
		{
		}
		else
		{
			Issue.record("Selection persistence must precede the history read")
		}
		if case .readConversationHistory = result.effects[2]
		{
		}
		else
		{
			Issue.record("Selection must request history synchronously")
		}
		#expect(result.domainEvents.count == 2)
		if case .conversationSelectionChanged("thread") = result.domainEvents[0]
		{
		}
		else
		{
			Issue.record("Conversation selection event must precede execution events")
		}
		if case .conversationContentChanged = result.domainEvents[1]
		{
		}
		else
		{
			Issue.record("Execution event was not kept at the selection boundary")
		}
		#expect(result.presentationCommands.count == 1)
	}

	@Test func restoredArchivedSelectionAppliesExecutionClearBeforeRefresh()
	{
		var model = fixture()
		let captured = context(model)
		model.lifecycle.pendingArchivedSelection = captured
		model.execution.state = .failed
		model.execution.needsReconciliation = true
		model.execution.hasUncertainRequest = true
		let result = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.archivedSelectionRestored(
				captured,
				archived: true,
				threadID: nil
			))
		)
		#expect(model.conversations.showingArchived)
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.execution.state == .ready)
		#expect(!model.execution.needsReconciliation)
		#expect(!model.execution.hasUncertainRequest)
		#expect(result.domainEvents.contains
		{
			if case .conversationSelectionChanged(nil) = $0
			{
				return true
			}
			return false
		})
	}

	@Test func acceptedHistoryReconcilesExecutionBeforeFinishingConversationRead()
	{
		var model = fixture()
		let captured = context(model)
		let read = ConversationReadOperation(
			context: captured,
			commandRevision: 0,
			purpose: .selection
		)
		model.conversations.pendingReads[read.key] = read
		model.conversations.pendingSelection = captured
		let result = WorkspaceFeatureComposition.reduce(
			&model,
			.conversations(.historyReceived(
				read,
				.succeeded(detail(status: "inProgress"))
			))
		)
		#expect(model.conversations.lastAppliedHistoryRequestID == captured.requestID)
		#expect(model.execution.activeThreadID == "thread")
		#expect(model.execution.activeTurnID == "turn")
		#expect(model.execution.owner?.submission.threadID == "thread")
		#expect(model.conversations.pendingReads[read.key]?.context == nil)
		let historyAccepted = result.domainEvents.firstIndex
		{
			if case .historyAccepted = $0
			{
				return true
			}
			return false
		}
		let readFinished = result.domainEvents.firstIndex
		{
			if case .conversationHistoryFinished = $0
			{
				return true
			}
			return false
		}
		#expect(historyAccepted != nil)
		#expect(readFinished != nil)
		if let historyAccepted, let readFinished
		{
			#expect(historyAccepted < readFinished)
		}
	}
}
