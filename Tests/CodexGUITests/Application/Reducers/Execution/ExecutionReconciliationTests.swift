import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ExecutionReconciliationTests
{
	private func fixture(state: ExecutionState) -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/reconciliation"
		))
		model.connection.isConnected = true
		model.executions.entries[.thread("worker")] = ExecutionModel()
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker",
			turnID: "live"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		model.executions.entries[.thread("worker")]!.activeThreadID = "worker"
		model.executions.entries[.thread("worker")]!.activeTurnID = "live"
		model.executions.entries[.thread("worker")]!.state = state
		model.executions.entries[.thread("worker")]!.needsReconciliation = true
		model.executions.entries[.thread("worker")]!.hasUncertainRequest = true
		model.executions.entries[.thread(
			"worker"
		)]!.statusMessage = "Instruction outcome is uncertain."
		model.conversations.selectedConversation = .thread("other")
		return (model, context)
	}

	private func detail(
		status: String?,
		active: Bool = false
	) -> ThreadDetail
	{
		var summary: [String: Any] = ["id": "worker", "cwd": "/tmp/reconciliation"]
		if active
		{
			summary["status"] = ["type": "active"]
		}
		return ThreadDetail(
			summary: ThreadSummary(json: summary)!,
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

	@Test(arguments: [false, true])
	func observedTurnDoesNotClearAnUncertainLocalRequest(_ retainsOwner: Bool) throws
	{
		var (model, context) = fixture(state: .failed)
		model.conversations.selectedConversation = .thread("worker")
		if !retainsOwner
		{
			model.execution.owner = nil
		}
		let running = try #require(CodexTurn(json: [
			"id": "live",
			"status": "inProgress",
			"items": [],
		]))
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnStarted(
					threadId: "worker",
					turn: running
				)
			))
		)
		#expect(model.execution.needsReconciliation)
		#expect(model.execution.hasUncertainRequest)
		let completed = try #require(CodexTurn(json: [
			"id": "live",
			"status": "completed",
			"items": [],
		]))
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnCompleted(
					threadId: "worker",
					turn: completed
				)
			))
		)
		#expect(model.execution.needsReconciliation)
		#expect(model.execution.hasUncertainRequest)
		#expect(!WorkspaceEligibility(model: model).canSend)
	}

	@Test func uncertainSteeringHistoryPreservesBusyOwnerAndStopTransport()
	{
		for state in [ExecutionState.running, .awaitingApproval, .awaitingAnswer, .stopping]
		{
			for status in [nil, "inProgress", "running", "completed"] as [String?]
			{
				var (model, context) = fixture(state: state)
				let result = history(
					detail(status: status),
					context: context,
					model: &model
				)
				#expect(model.executions.entries[.thread("worker")]!.owner?.submission == context)
				#expect(model.executions.entries[.thread("worker")]!.activeThreadID == "worker")
				#expect(model.executions.entries[.thread("worker")]!.activeTurnID == "live")
				#expect(model.executions.entries[.thread("worker")]!.state == state)
				#expect(model.executions.entries[.thread("worker")]!.needsReconciliation)
				#expect(model.executions.entries[.thread("worker")]!.hasUncertainRequest)
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
					#expect(model.executions.entries[.thread("worker")]!.state == .stopping)
					#expect(model.executions.entries[.thread("worker")]!.pendingInterruption?
						.context.turnID == "live")
					let pending = model.executions.entries[.thread("worker")]!.pendingInterruption?
						.context
					_ = history(
						detail(status: status),
						context: context,
						model: &model
					)
					#expect(model.executions.entries[.thread("worker")]!.state == .stopping)
					#expect(model.executions.entries[.thread("worker")]!.pendingInterruption?
						.context == pending)
					#expect(model.executions.entries[.thread("worker")]!.stopRequested)
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
			for status in [nil, "completed", "inProgress", "running"] as [String?]
			{
				var (model, context) = fixture(state: state)
				_ = history(
					detail(status: status),
					context: context,
					model: &model
				)
				if status == "inProgress" || status == "running"
				{
					#expect(model.executions.entries[.thread("worker")]!.state == .failed)
					#expect(model.executions.entries[.thread("worker")]!.activeThreadID == "worker")
					#expect(model.executions.entries[.thread("worker")]!.needsReconciliation)
				}
				else
				{
					#expect(model.executions.entries[.thread("worker")]!.state == .ready)
					#expect(model.executions.entries[.thread("worker")]!.activeThreadID == nil)
					#expect(!model.executions.entries[.thread("worker")]!.needsReconciliation)
					#expect(!model.executions.entries[.thread("worker")]!.hasUncertainRequest)
				}
			}
		}
	}

	@Test(arguments: ["inProgress", "running"])
	func authoritativeRunningAliasesRecoverLiveOwnerAndRetainCommandBarrier(status: String)
	{
		var (model, context) = fixture(state: .disconnected)
		model.executions.entries[.thread("worker")]!.owner = nil
		model.executions.entries[.thread("worker")]!.commandLifetime = TaskCommandLifetime(
			pending: [TaskCommandOwnership(
				threadID: "worker",
				turnID: "live",
				itemID: "command"
			)]
		)
		_ = history(
			detail(
				status: status,
				active: true
			),
			context: context,
			model: &model
		)
		let execution = model.execution(for: .thread("worker"))
		#expect(execution.state == .running)
		#expect(execution.activeTurnID == "live")
		#expect(execution.owner?.submission == context)
		#expect(!execution.needsReconciliation)
		#expect(execution.commandLifetime.hasPendingCommands)
		#expect(model.blocksExecutionCleanup)
		model.conversations.selectedConversation = .thread("worker")
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnCompleted(
					threadId: "worker",
					turn: detail(status: "completed").turns[0]
				)
			))
		)
		#expect(model.execution.needsReconciliation)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnStarted(
					threadId: "worker",
					turn: CodexTurn(
						id: "next-turn",
						status: "inProgress",
						items: [],
						error: nil
					)
				)
			))
		)
		#expect(model.execution.activeTurnID == "next-turn")
		#expect(model.execution.needsReconciliation)
		#expect(model.execution.commandLifetime.pending.contains(TaskCommandOwnership(
			threadID: "worker",
			turnID: "live",
			itemID: "command"
		)))
		#expect(!WorkspaceEligibility(model: model).canSteer)
	}

	@Test(arguments: ["interrupted", "stopped", "cancelled"])
	func terminalEventEndsLiveOwnershipAndAllowsHistoryReconciliation(status: String)
	{
		var (model, context) = fixture(state: .stopping)
		let terminal = detail(status: status).turns[0]
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
		#expect(model.executions.entries[.thread("worker")]!.activeTurnID == nil)
		#expect(model.executions.entries[.thread("worker")]!.agentOutcome == .stopped)
		_ = history(
			detail(status: status),
			context: context,
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!.state == .ready)
		#expect(!model.executions.entries[.thread("worker")]!.needsReconciliation)
		#expect(model.executions.entries[.thread("worker")]!.activeThreadID == nil)
	}
}
