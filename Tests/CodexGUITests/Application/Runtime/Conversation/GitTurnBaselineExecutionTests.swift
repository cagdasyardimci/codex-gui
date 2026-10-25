import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
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
		try await withBaselineExecution(
			task,
			baseline: baseline,
			runner: runner
		)
		{
			try await baseline.waitForCapture()
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
		try await withBaselineExecution(
			task,
			baseline: baseline,
			runner: runner
		)
		{
			try await baseline.waitForCapture()
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
			try await withBaselineExecution(
				task,
				baseline: baseline,
				runner: runner
			)
			{
				try await baseline.waitForCapture()
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
	}

	private func withBaselineExecution(
		_ task: Task<Void, Error>,
		baseline: SuspendedGitTurnBaselineService,
		runner: WorkspaceEffectRunner,
		operation: () async throws -> Void
	) async throws
	{
		let completion = Task
		{
			_ = await task.result
			await baseline.executionFinished()
		}
		func cleanup() async
		{
			task.cancel()
			await baseline.releasePendingCapture()
			_ = await task.result
			await completion.value
			runner.shutdown()
		}
		do
		{
			try await operation()
			await cleanup()
		}
		catch
		{
			await cleanup()
			throw error
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
	private var captureWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]
	private var didFinishExecution = false
	private var isTearingDown = false

	func capture(_ request: GitTurnBaselineCaptureRequest) async -> GitTurnBaselineResult
	{
		guard !isTearingDown
		else
		{
			return .unavailable(.cancelled)
		}
		capturedRequest = request
		return await withCheckedContinuation
		{
			continuation in
			captureContinuation = continuation
			notifyCaptureWaiters()
		}
	}

	func waitForCapture() async throws
	{
		try Task.checkCancellation()
		guard capturedRequest == nil
		else
		{
			return
		}
		guard !didFinishExecution
		else
		{
			throw CaptureCheckpointFailure.executionFinishedBeforeCapture
		}
		let id = UUID()
		let checkpoint = AsyncStream<Void>.makeStream()
		captureWaiters[id] = checkpoint.continuation
		defer
		{
			captureWaiters.removeValue(forKey: id)
			checkpoint.continuation.finish()
		}
		for await _ in checkpoint.stream
		{
			break
		}
		try Task.checkCancellation()
		guard capturedRequest != nil
		else
		{
			throw CaptureCheckpointFailure.executionFinishedBeforeCapture
		}
	}

	func executionFinished()
	{
		didFinishExecution = true
		notifyCaptureWaiters()
	}

	func releasePendingCapture()
	{
		isTearingDown = true
		finishCapture(.unavailable(.cancelled))
		notifyCaptureWaiters()
	}

	private func notifyCaptureWaiters()
	{
		let waiters = Array(captureWaiters.values)
		captureWaiters.removeAll()
		for waiter in waiters
		{
			waiter.yield(())
			waiter.finish()
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

	private enum CaptureCheckpointFailure: Error
	{
		case executionFinishedBeforeCapture
	}
}
