import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct GitTurnBaselineLifecycleTests
{
	@Test func acknowledgedOwnerBindsActualTurnWhileAnotherChatIsSelected()
	{
		var (model, context) = fixture()
		let reference = reference(context)
		let result = acknowledge(
			reference,
			context: context,
			model: &model
		)
		#expect(result.effects.contains
		{
			if case .bindGitTurnBaseline(let operation) = $0
			{
				return operation.reference == reference && operation.turnID == "actual-turn"
			}
			return false
		})
		#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings["worker"]?
			.turnID == "actual-turn")
		#expect(model.executions.entries[.thread("worker")]!
			.gitTurnBaselineRevisions["worker"] == 1)
	}

	@Test func capturedPhysicalRootBindsWhenWorkspaceUsesTmpAlias()
	{
		var (model, originalContext) = fixture()
		let checkoutPath = "/tmp/codex-gui-baseline-alias"
		let physicalRoot = WorkspaceFileIdentity.canonicalRootPath(
			URL(fileURLWithPath: checkoutPath)
		)
		#expect(physicalRoot != checkoutPath)
		model.identity = WorkspaceIdentity(
			sessionID: model.identity.sessionID,
			canonicalCheckoutPath: checkoutPath
		)
		let context = OperationContext(
			workspace: model.identity,
			generation: originalContext.generation,
			requestID: originalContext.requestID,
			threadID: "worker"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		let captured = reference(
			context,
			repositoryRoot: physicalRoot
		)
		let result = acknowledge(
			captured,
			context: context,
			model: &model
		)
		#expect(result.effects.contains
		{
			if case .bindGitTurnBaseline(let operation) = $0
			{
				return operation.reference == captured && operation.turnID == "actual-turn"
			}
			return false
		})
		let bound = captured.bound(to: "actual-turn")
		GitTurnBaselineLifecycle.finishBinding(
			.captured(bound),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings["worker"]?
			.result == .captured(bound))
	}

	@Test func bindingCompletionPublishesOnceAndRejectsWrongTurnOrGeneration()
	{
		var (model, context) = fixture()
		let reference = reference(context)
		_ = acknowledge(
			reference,
			context: context,
			model: &model
		)
		GitTurnBaselineLifecycle.finishBinding(
			.captured(reference.bound(to: "actual-turn")),
			context: context,
			threadID: "worker",
			turnID: "wrong-turn",
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!
			.gitTurnBaselineRevisions["worker"] == 1)
		GitTurnBaselineLifecycle.finishBinding(
			.captured(reference.bound(to: "actual-turn")),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!
			.gitTurnBaselineRevisions["worker"] == 2)
		#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings["worker"]?
			.result
			== .captured(reference.bound(to: "actual-turn")))
		GitTurnBaselineLifecycle.finishBinding(
			.captured(reference.bound(to: "actual-turn")),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!
			.gitTurnBaselineRevisions["worker"] == 2)
		model.connection.generation += 1
		GitTurnBaselineLifecycle.finishBinding(
			.unavailable(.oversized),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.executions.entries[.thread("worker")]!
			.gitTurnBaselineRevisions["worker"] == 2)
	}

	@Test func unavailableCaptureReasonSurvivesAcknowledgementWithoutBinding()
	{
		var (model, context) = fixture()
		let acknowledgement = SubmissionAcknowledgement(
			thread: thread(),
			turn: CodexTurn(
				id: "actual-turn",
				status: "inProgress",
				items: [],
				error: nil
			),
			gitTurnBaselineResult: .unavailable(.oversized)
		)
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.submissionAcknowledged(
				context,
				acknowledgement
			))
		)
		#expect(result.effects.isEmpty)
		#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings["worker"]?
			.result == .unavailable(.oversized))
	}

	@Test func uncertainCaptureBindsOnlyOneNewTurnAndDiscardsAbsentOrAmbiguousTurns()
	{
		for newTurnIDs in [["new"], [], ["new", "other"]]
		{
			var (model, context) = fixture()
			let captured = reference(context)
			model.executions.entries[.thread("worker")]!
				.pendingGitTurnBaselineCapture = PendingGitTurnBaselineCapture(
					context: context,
					reference: captured,
					previousTurnIDs: ["old"]
				)
			model.executions.entries[.thread("worker")]!.hasUncertainRequest = true
			model.executions.entries[.thread("worker")]!.needsReconciliation = true
			let turns = (["old"] + newTurnIDs).map
			{
				CodexTurn(
					id: $0,
					status: "completed",
					items: [],
					error: nil
				)
			}
			var result = WorkspaceReduction()
			GitTurnBaselineLifecycle.resolvePendingCapture(
				ThreadDetail(
					summary: thread(),
					turns: turns,
					nextTurnsCursor: nil
				),
				model: &model,
				result: &result
			)
			#expect(model.executions.entries[.thread("worker")]!
				.pendingGitTurnBaselineCapture == nil)
			if newTurnIDs.count == 1
			{
				#expect(result.effects.contains
				{
					if case .bindGitTurnBaseline(let operation) = $0
					{
						return operation.turnID == "new" && operation.reference == captured
					}
					return false
				})
			}
			else
			{
				#expect(result.effects.contains
				{
					if case .discardGitTurnBaseline(let capture) = $0
					{
						return capture.reference == captured
					}
					return false
				})
			}
		}
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/neutral/repository"
		))
		model.connection.isConnected = true
		model.executions.entries[.thread("worker")] = ExecutionModel()
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		model.executions.entries[.thread("worker")]!.activeThreadID = "worker"
		model.executions.entries[.thread("worker")]!.state = .running
		model.conversations.selectedConversation = .thread("other")
		return (model, context)
	}

	private func reference(
		_ context: OperationContext,
		repositoryRoot: String? = nil
	) -> GitTurnBaselineReference
	{
		GitTurnBaselineReference(
			identity: GitTurnBaselineIdentity(
				id: UUID(),
				workspaceSessionID: context.workspace.sessionID,
				repositoryRoot: repositoryRoot ?? context.workspace.canonicalCheckoutPath!,
				executionGeneration: context.generation,
				submissionRequestID: context.requestID,
				threadID: "worker"
			),
			capturedAt: Date(timeIntervalSince1970: 0),
			trackedFileCount: 1,
			byteCount: 10,
			acceptedTurnID: nil
		)
	}

	private func thread() -> ThreadSummary
	{
		ThreadSummary(json: ["id": "worker", "cwd": "/neutral/repository"])!
	}

	private func acknowledge(
		_ reference: GitTurnBaselineReference,
		context: OperationContext,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ExecutionReducer.reduce(
			&model,
			.execution(.submissionAcknowledged(
				context,
				SubmissionAcknowledgement(
					thread: thread(),
					turn: CodexTurn(
						id: "actual-turn",
						status: "inProgress",
						items: [],
						error: nil
					),
					gitTurnBaseline: reference,
					gitTurnBaselineResult: .captured(reference)
				)
			))
		)
	}
}
