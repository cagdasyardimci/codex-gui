import Foundation
import Testing

@testable import CodexGUI

@MainActor
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
		#expect(model.execution.gitTurnBaselineBindings["worker"]?.turnID == "actual-turn")
		#expect(model.execution.gitTurnBaselineRevisions["worker"] == 1)
	}

	@Test func staleWorkspaceGenerationRequestAndTurnMismatchNeverBind()
	{
		for mismatch in 0 ... 3
		{
			var (model, context) = fixture()
			let reference = reference(context)
			switch mismatch
			{
			case 0:
				model.identity = WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: context.workspace.canonicalCheckoutPath
				)
			case 1: model.connection.generation += 1
			case 2: model.execution.owner?.submission = OperationContext(
					workspace: context.workspace,
					generation: context.generation,
					requestID: UUID()
				)
			default: model.execution.activeTurnID = "different-turn"
			}
			let result = acknowledge(
				reference,
				context: context,
				model: &model
			)
			#expect(!result.effects.contains
			{
				if case .bindGitTurnBaseline = $0
				{
					return true
				}
				return false
			})
			#expect(model.execution.gitTurnBaselineBindings.isEmpty)
		}
	}

	@Test func externalTurnObservationWithoutAcknowledgementDoesNotBind()
	{
		var (model, context) = fixture()
		model.execution.owner = nil
		let turn = CodexTurn(
			id: "external",
			status: "inProgress",
			items: [],
			error: nil
		)
		let result = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				.turnStarted(
					threadId: "worker",
					turn: turn
				),
				observedAt: nil
			))
		)
		#expect(!result.effects.contains
		{
			if case .bindGitTurnBaseline = $0
			{
				return true
			}
			return false
		})
		#expect(model.execution.gitTurnBaselineBindings.isEmpty)
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
		#expect(model.execution.gitTurnBaselineRevisions["worker"] == 1)
		GitTurnBaselineLifecycle.finishBinding(
			.captured(reference.bound(to: "actual-turn")),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.execution.gitTurnBaselineRevisions["worker"] == 2)
		#expect(model.execution.gitTurnBaselineBindings["worker"]?.result
			== .captured(reference.bound(to: "actual-turn")))
		GitTurnBaselineLifecycle.finishBinding(
			.captured(reference.bound(to: "actual-turn")),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.execution.gitTurnBaselineRevisions["worker"] == 2)
		model.connection.generation += 1
		GitTurnBaselineLifecycle.finishBinding(
			.unavailable(.oversized),
			context: context,
			threadID: "worker",
			turnID: "actual-turn",
			model: &model
		)
		#expect(model.execution.gitTurnBaselineRevisions["worker"] == 2)
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
		#expect(model.execution.gitTurnBaselineBindings["worker"]?
			.result == .unavailable(.oversized))
	}

	@Test func stopAfterRemoteSendStillBindsTheAcknowledgedTurn()
	{
		var (model, context) = fixture()
		model.execution.state = .stopping
		model.execution.stopRequested = true
		model.execution.stopContext = context
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
	}

	@Test func uncertainCaptureBindsOnlyOneNewTurnAndDiscardsAbsentOrAmbiguousTurns()
	{
		for newTurnIDs in [["new"], [], ["new", "other"]]
		{
			var (model, context) = fixture()
			let captured = reference(context)
			model.execution.pendingGitTurnBaselineCapture = PendingGitTurnBaselineCapture(
				context: context,
				reference: captured,
				previousTurnIDs: ["old"]
			)
			model.execution.hasUncertainRequest = true
			model.execution.needsReconciliation = true
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
			#expect(model.execution.pendingGitTurnBaselineCapture == nil)
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

	@Test func ordinaryHistoryCannotResolveAnUncertainCaptureWithoutRecoveryState()
	{
		var (model, context) = fixture()
		let captured = reference(context)
		model.execution.pendingGitTurnBaselineCapture = PendingGitTurnBaselineCapture(
			context: context,
			reference: captured,
			previousTurnIDs: ["old"]
		)
		var result = WorkspaceReduction()
		GitTurnBaselineLifecycle.resolvePendingCapture(
			ThreadDetail(
				summary: thread(),
				turns: [CodexTurn(
					id: "new",
					status: "completed",
					items: [],
					error: nil
				)],
				nextTurnsCursor: nil
			),
			model: &model,
			result: &result
		)
		#expect(model.execution.pendingGitTurnBaselineCapture?.reference == captured)
		#expect(result.effects.isEmpty)
	}

	@Test func localStopSettlesExecutionAndReleasesSubmissionWithoutClearingDraft()
	{
		var (model, context) = fixture()
		let draft = ComposerDraft(text: "Keep this request")
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread("worker"),
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.execution.submissionRequest = context
		model.execution.state = .stopping
		model.execution.stopRequested = true
		model.composer.pendingSubmissions[context.requestID] = submission
		model.composer.submissionConversations[context.requestID] = .thread("worker")
		model.composer.drafts[.thread("worker")] = draft
		let action = WorkspaceAction.execution(.submissionCancelledBeforeSend(context))
		_ = ExecutionReducer.reduce(
			&model,
			action
		)
		let composerResult = ComposerReducer.reduce(
			&model,
			action
		)
		#expect(model.execution.state == .completed)
		#expect(!model.execution.hasUncertainRequest)
		#expect(model.composer.drafts[.thread("worker")]?.text == draft.text)
		#expect(composerResult.effects.contains
		{
			if case .releaseSubmission(let operation) = $0
			{
				return operation.submission.context.isSameRequest(as: context)
			}
			return false
		})
	}

	private func fixture() -> (WorkspaceModel, OperationContext)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/neutral/repository"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "worker"
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.activeThreadID = "worker"
		model.execution.state = .running
		model.conversations.selectedConversation = .thread("other")
		return (model, context)
	}

	private func reference(_ context: OperationContext) -> GitTurnBaselineReference
	{
		GitTurnBaselineReference(
			identity: GitTurnBaselineIdentity(
				id: UUID(),
				workspaceSessionID: context.workspace.sessionID,
				repositoryRoot: context.workspace.canonicalCheckoutPath!,
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
