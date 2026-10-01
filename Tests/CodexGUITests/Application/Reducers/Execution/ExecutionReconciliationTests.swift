import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ExecutionReconciliationTests
{
	private func fixture(state: ExecutionState) -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/reconciliation"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker",
			turnID: "live"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.activeThreadID = "worker"
		model.execution.activeTurnID = "live"
		model.execution.state = state
		model.execution.needsReconciliation = true
		model.execution.hasUncertainRequest = true
		model.execution.statusMessage = "Instruction outcome is uncertain."
		model.conversations.selectedConversation = .thread("other")
		return (model, context)
	}

	private func detail(status: String?) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": "worker", "cwd": "/tmp/reconciliation"])!,
			turns: status.map
			{
				[CodexTurn(
					id: "live",
					status: $0,
					items: [],
					error: nil
				)]
			} ?? [],
			nextTurnsCursor: nil
		)
	}

	private func history(
		_ detail: ThreadDetail,
		context: OperationContext,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				ReconciliationOperation(
					context: context,
					commandRevision: 0
				),
				detail
			))
		)
	}

	@Test func uncertainSteeringHistoryPreservesBusyOwnerAndStopTransport()
	{
		for state in [ExecutionState.running, .awaitingApproval, .awaitingAnswer, .stopping]
		{
			for status in [nil, "inProgress", "completed"] as [String?]
			{
				var (model, context) = fixture(state: state)
				let result = history(
					detail(status: status),
					context: context,
					model: &model
				)
				#expect(model.execution.owner?.submission == context)
				#expect(model.execution.activeThreadID == "worker")
				#expect(model.execution.activeTurnID == "live")
				#expect(model.execution.state == state)
				#expect(model.execution.needsReconciliation)
				#expect(model.execution.hasUncertainRequest)
				#expect(result.domainEvents.contains
				{
					if case .historyAccepted = $0
					{
						return true
					}
					return false
				})
				if state != .stopping
				{
					let stop = ExecutionReducer.reduce(
						&model,
						.execution(.stopRequested(context))
					)
					#expect(model.execution.state == .stopping)
					#expect(model.execution.pendingInterruption?.context.turnID == "live")
					let pending = model.execution.pendingInterruption?.context
					_ = history(
						detail(status: status),
						context: context,
						model: &model
					)
					#expect(model.execution.state == .stopping)
					#expect(model.execution.pendingInterruption?.context == pending)
					#expect(model.execution.stopRequested)
					#expect(stop.effects.contains
					{
						if case .interrupt = $0
						{
							return true
						}
						return false
					})
				}
			}
		}
	}

	@Test func failedAndDisconnectedOwnersStillRecoverAuthoritativeHistory()
	{
		for state in [ExecutionState.failed, .disconnected]
		{
			for status in [nil, "completed", "inProgress"] as [String?]
			{
				var (model, context) = fixture(state: state)
				_ = history(
					detail(status: status),
					context: context,
					model: &model
				)
				if status == "inProgress"
				{
					#expect(model.execution.state == .failed)
					#expect(model.execution.activeThreadID == "worker")
					#expect(model.execution.needsReconciliation)
				}
				else
				{
					#expect(model.execution.state == .ready)
					#expect(model.execution.activeThreadID == nil)
					#expect(!model.execution.needsReconciliation)
					#expect(!model.execution.hasUncertainRequest)
				}
			}
		}
	}

	@Test func terminalEventEndsLiveOwnershipAndAllowsHistoryReconciliation()
	{
		var (model, context) = fixture(state: .stopping)
		let terminal = detail(status: "interrupted").turns[0]
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnCompleted(
					threadId: "worker",
					turn: terminal
				)
			))
		)
		#expect(model.execution.activeTurnID == nil)
		#expect(model.execution.agentOutcome == .stopped)
		_ = history(
			detail(status: "interrupted"),
			context: context,
			model: &model
		)
		#expect(model.execution.state == .ready)
		#expect(!model.execution.needsReconciliation)
		#expect(model.execution.activeThreadID == nil)
	}
}
