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
			repositoryRoot: physicalRoot,
			workspaceCheckoutPath: checkoutPath
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

	@Test func capturedOwnerRemainsDeterministicAfterItsSymlinkChanges() async throws
	{
		let paths = try await BackgroundTestWork.perform
		{
			let directory = FileManager.default.temporaryDirectory
				.appendingPathComponent("BaselineOwner-\(UUID())")
			let first = directory.appendingPathComponent("first")
			let second = directory.appendingPathComponent("second")
			try FileManager.default.createDirectory(
				at: first,
				withIntermediateDirectories: true
			)
			do
			{
				try FileManager.default.createDirectory(
					at: second,
					withIntermediateDirectories: true
				)
				let alias = directory.appendingPathComponent("alias")
				try FileManager.default.createSymbolicLink(
					at: alias,
					withDestinationURL: first
				)
				let physicalRoot = WorkspaceFileIdentity.canonicalRootPath(alias)
				try FileManager.default.removeItem(at: alias)
				try FileManager.default.createSymbolicLink(
					at: alias,
					withDestinationURL: second
				)
				return (directory, alias.path, physicalRoot)
			}
			catch
			{
				try? FileManager.default.removeItem(at: directory)
				throw error
			}
		}
		defer
		{
			try? FileManager.default.removeItem(at: paths.0)
		}
		var (model, previous) = fixture()
		model.identity = WorkspaceIdentity(
			sessionID: previous.workspace.sessionID,
			canonicalCheckoutPath: paths.1
		)
		let context = OperationContext(
			workspace: model.identity,
			generation: previous.generation,
			requestID: previous.requestID,
			threadID: "worker"
		)
		model.executions.entries[.thread("worker")]!.owner = ExecutionOwner(submission: context)
		let captured = reference(
			context,
			repositoryRoot: paths.2,
			workspaceCheckoutPath: paths.1
		)
		let result = acknowledge(
			captured,
			context: context,
			model: &model
		)
		#expect(result.effects.contains
		{
			if case .bindGitTurnBaseline = $0
			{
				return true
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
			case 2: model.executions.entries[.thread("worker")]!.owner?
				.submission = OperationContext(
					workspace: context.workspace,
					generation: context.generation,
					requestID: UUID()
				)
			default: model.executions.entries[.thread("worker")]!.activeTurnID = "different-turn"
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
			#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings.isEmpty)
		}
	}

	@Test func externalTurnObservationWithoutAcknowledgementDoesNotBind()
	{
		var (model, context) = fixture()
		model.executions.entries[.thread("worker")]!.owner = nil
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
		#expect(model.executions.entries[.thread("worker")]!.gitTurnBaselineBindings.isEmpty)
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

	@Test func stopAfterRemoteSendStillBindsTheAcknowledgedTurn()
	{
		var (model, context) = fixture()
		model.executions.entries[.thread("worker")]!.state = .stopping
		model.executions.entries[.thread("worker")]!.stopRequested = true
		model.executions.entries[.thread("worker")]!.stopContext = context
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

	@Test func ordinaryHistoryCannotResolveAnUncertainCaptureWithoutRecoveryState()
	{
		var (model, context) = fixture()
		let captured = reference(context)
		model.executions.entries[.thread("worker")]!
			.pendingGitTurnBaselineCapture = PendingGitTurnBaselineCapture(
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
		#expect(model.executions.entries[.thread("worker")]!.pendingGitTurnBaselineCapture?
			.reference == captured)
		#expect(result.effects.isEmpty)
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
		repositoryRoot: String? = nil,
		workspaceCheckoutPath: String? = nil
	) -> GitTurnBaselineReference
	{
		GitTurnBaselineReference(
			identity: GitTurnBaselineIdentity(
				id: UUID(),
				workspaceSessionID: context.workspace.sessionID,
				repositoryRoot: repositoryRoot ?? context.workspace.canonicalCheckoutPath!,
				executionGeneration: context.generation,
				submissionRequestID: context.requestID,
				threadID: "worker",
				workspaceCheckoutPath: workspaceCheckoutPath
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
