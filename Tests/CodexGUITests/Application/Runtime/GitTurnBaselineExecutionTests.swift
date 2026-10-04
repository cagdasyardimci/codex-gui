import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct GitTurnBaselineExecutionTests
{
	@Test func capturedBytesRemainOwnedByThePreparedThreadAndAcknowledgedTurn() async throws
	{
		let service = MockCodexService()
		let baseline = SuspendedGitTurnBaselineService()
		let prepared = prepared(service)
		let reference = reference(prepared)
		let runner = runner(
			service,
			baseline: baseline
		)
		var action: WorkspaceAction?
		let task = Task
		{
			action = try await runner.perform(
				.startSubmission(prepared),
				context: prepared.submission.context,
				persistenceTask: nil,
				contextLoadTask: nil,
				managedWorkspace: nil
			)
		}
		await baseline.waitForCapture()
		let request = await baseline.capturedRequest
		#expect(request?.context == prepared.submission.context)
		#expect(request?.threadID == prepared.thread.summary.id)
		#expect(request?.repositoryRoot == prepared.submission.context.workspace
			.canonicalCheckoutPath)
		#expect(service.turnStartCount == 0)
		await baseline.finishCapture(.captured(reference))
		try await task.value
		guard let action, case .execution(.submissionAcknowledged(
			_,
			let acknowledgement
		)) = action
		else
		{
			Issue.record("Expected the captured submission acknowledgement.")
			return
		}
		#expect(acknowledgement.gitTurnBaseline == reference)
		#expect(acknowledgement.turn.id == service.nextTurn.id)
		#expect(acknowledgement.thread.id == prepared.thread.summary.id)
	}

	@Test func captureCompletesBeforeBackendSendAndUnavailableCaptureDoesNotBlock() async throws
	{
		let service = MockCodexService()
		let baseline = SuspendedGitTurnBaselineService()
		let prepared = prepared(service)
		let runner = runner(
			service,
			baseline: baseline
		)
		var action: WorkspaceAction?
		let task = Task
		{
			action = try await runner.perform(
				.startSubmission(prepared),
				context: prepared.submission.context,
				persistenceTask: nil,
				contextLoadTask: nil,
				managedWorkspace: nil
			)
		}
		await baseline.waitForCapture()
		#expect(service.turnStartCount == 0)
		await baseline.finishCapture(.unavailable(.oversized))
		try await task.value
		#expect(service.turnStartCount == 1)
		guard let action, case .execution(.submissionAcknowledged(
			let context,
			let acknowledgement
		)) = action
		else
		{
			Issue.record("Expected the actual backend acknowledgement.")
			return
		}
		#expect(context.isSameRequest(as: prepared.submission.context))
		#expect(acknowledgement.turn.id == service.nextTurn.id)
		#expect(acknowledgement.gitTurnBaseline == nil)
		#expect(acknowledgement.gitTurnBaselineResult == .unavailable(.oversized))
	}

	@Test func ownershipChangeDuringCapturePreventsBackendSend() async throws
	{
		let service = MockCodexService()
		let baseline = SuspendedGitTurnBaselineService()
		let prepared = prepared(service)
		var current = true
		let runner = runner(
			service,
			baseline: baseline,
			isCurrent:
			{
				_ in current
			}
		)
		let task = Task
		{
			_ = try await runner.perform(
				.startSubmission(prepared),
				context: prepared.submission.context,
				persistenceTask: nil,
				contextLoadTask: nil,
				managedWorkspace: nil
			)
		}
		await baseline.waitForCapture()
		current = false
		let reference = reference(prepared)
		await baseline.finishCapture(.captured(reference))
		do
		{
			_ = try await task.value
			Issue.record("A superseded capture must not submit a turn.")
		}
		catch is CancellationError
		{
		}
		#expect(service.turnStartCount == 0)
		#expect(await baseline.discardedIDs == [reference.identity.id])
	}

	@Test func cancellationDuringCapturePreventsBackendSend() async throws
	{
		let service = MockCodexService()
		let baseline = SuspendedGitTurnBaselineService()
		let prepared = prepared(service)
		let runner = runner(
			service,
			baseline: baseline
		)
		let task = Task
		{
			_ = try await runner.perform(
				.startSubmission(prepared),
				context: prepared.submission.context,
				persistenceTask: nil,
				contextLoadTask: nil,
				managedWorkspace: nil
			)
		}
		await baseline.waitForCapture()
		task.cancel()
		await baseline.finishCapture(.unavailable(.oversized))
		do
		{
			_ = try await task.value
			Issue.record("A canceled capture must not submit a turn.")
		}
		catch is CancellationError
		{
		}
		#expect(service.turnStartCount == 0)
	}

	@Test func stopDuringCaptureCancelsBeforeSendAndDiscardsCapture() async throws
	{
		let service = MockCodexService()
		let baseline = SuspendedGitTurnBaselineService()
		let prepared = prepared(service)
		let reference = reference(prepared)
		var stopped = false
		let runner = runner(
			service,
			baseline: baseline,
			isStopped:
			{
				_ in stopped
			}
		)
		var action: WorkspaceAction?
		let task = Task
		{
			action = try await runner.perform(
				.startSubmission(prepared),
				context: prepared.submission.context,
				persistenceTask: nil,
				contextLoadTask: nil,
				managedWorkspace: nil
			)
		}
		await baseline.waitForCapture()
		stopped = true
		await baseline.finishCapture(.captured(reference))
		try await task.value
		guard let action, case .execution(.submissionCancelledBeforeSend(let context)) = action
		else
		{
			Issue.record("Stop must settle the unsent submission locally.")
			return
		}
		#expect(context.isSameRequest(as: prepared.submission.context))
		#expect(service.turnStartCount == 0)
		#expect(await baseline.discardedIDs == [reference.identity.id])
	}

	@Test func rejectedStartDiscardsCaptureButTimedOutStartRetainsOwnedCapture() async throws
	{
		for (error, uncertain) in [
			(AppServerError.requestRejected("rejected"), false),
			(AppServerError.requestTimedOut("turn/start"), true),
		]
		{
			let service = MockCodexService()
			service.startTurnError = error
			let baseline = SuspendedGitTurnBaselineService()
			let prepared = prepared(service)
			let reference = reference(prepared)
			let runner = runner(
				service,
				baseline: baseline
			)
			let task = Task
			{
				_ = try await runner.perform(
					.startSubmission(prepared),
					context: prepared.submission.context,
					persistenceTask: nil,
					contextLoadTask: nil,
					managedWorkspace: nil
				)
			}
			await baseline.waitForCapture()
			await baseline.finishCapture(.captured(reference))
			do
			{
				_ = try await task.value
				Issue.record("The failed start must retain its failure result.")
			}
			catch let failure as SubmissionStartFailure
			{
				#expect(failure.failure.outcomeIsUncertain == uncertain)
				#expect(failure.pendingCapture?.reference == (uncertain ? reference : nil))
				#expect(failure.pendingCapture?.context == (uncertain
						? prepared.submission.context : nil))
			}
			#expect(service.turnStartCount == 1)
			#expect(await baseline.discardedIDs == (uncertain ? [] : [reference.identity.id]))
		}
	}

	private func reference(_ prepared: PreparedSubmission) -> GitTurnBaselineReference
	{
		let context = prepared.submission.context
		return GitTurnBaselineReference(
			identity: GitTurnBaselineIdentity(
				id: UUID(),
				workspaceSessionID: context.workspace.sessionID,
				repositoryRoot: context.workspace.canonicalCheckoutPath!,
				executionGeneration: context.generation,
				submissionRequestID: context.requestID,
				threadID: prepared.thread.summary.id
			),
			capturedAt: .distantPast,
			trackedFileCount: 1,
			byteCount: 12,
			acceptedTurnID: nil
		)
	}

	private func prepared(_ service: MockCodexService) -> PreparedSubmission
	{
		let context = OperationContext(
			workspace: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/neutral/repository"
			),
			generation: 1,
			requestID: UUID(),
			threadID: service.thread.id
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread(service.thread.id),
			draft: ComposerDraft(),
			inputs: [.text("Neutral fixture")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		return PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: service.thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
	}

	private func runner(
		_ service: MockCodexService,
		baseline: any GitTurnBaselineService,
		isCurrent: @escaping (OperationContext) -> Bool =
		{
			_ in true
		},
		isStopped: @escaping (OperationContext) -> Bool =
		{
			_ in false
		}
	) -> WorkspaceEffectRunner
	{
		WorkspaceEffectRunner(
			service: service,
			gitTurnBaselineService: baseline,
			isSubmissionCurrent: isCurrent,
			isSubmissionStopped: isStopped,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				_, completion in completion()
			}
		)
	}
}

private actor SuspendedGitTurnBaselineService: GitTurnBaselineService
{
	private(set) var capturedRequest: GitTurnBaselineCaptureRequest?
	private(set) var discardedIDs: [UUID] = []
	private var captureContinuation: CheckedContinuation<GitTurnBaselineResult, Never>?
	private var captureWaiters: [CheckedContinuation<Void, Never>] = []

	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	{
		capturedRequest = request
		return await withCheckedContinuation
		{
			continuation in
			captureContinuation = continuation
			for waiter in captureWaiters
			{
				waiter.resume()
			}
			captureWaiters.removeAll()
		}
	}

	func waitForCapture() async
	{
		guard captureContinuation == nil
		else
		{
			return
		}
		await withCheckedContinuation
		{
			captureWaiters.append($0)
		}
	}

	func finishCapture(_ result: GitTurnBaselineResult)
	{
		captureContinuation?.resume(returning: result)
		captureContinuation = nil
	}

	func bind(
		_ reference: GitTurnBaselineReference,
		turnID: String
	) async -> GitTurnBaselineResult
	{
		.captured(reference.bound(to: turnID))
	}

	func lookup(
		repositoryRoot: String,
		threadID: String,
		turnID: String
	) async -> GitTurnBaselineReference?
	{
		nil
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		.unavailable(.lastTurnUnavailable)
	}

	func discard(_ reference: GitTurnBaselineReference) async
	{
		discardedIDs.append(reference.identity.id)
	}
}
