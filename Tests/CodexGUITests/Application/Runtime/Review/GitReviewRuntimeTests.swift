import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
struct GitReviewRuntimeTests
{

	@Test @MainActor
	func turnChangeAndFinishedBindingRetryFailedLastTurnExactlyOnce() async throws
	{
		let runtime = GitReviewRuntime(
			service: MissingRevisionComparisonService(),
			automaticRefreshEnabled: true
		)
		try await waitForFailure(runtime)
		{
			runtime.activate(
				owner: owner(),
				lastTurnID: "first",
				baselineRevision: 1
			)
		}
		try await waitForFailure(runtime)
		{
			runtime.selectScope(.lastTurn)
		}
		let initialGeneration = runtime.state.generation
		try await waitForFailure(runtime)
		{
			runtime.updateContext(
				lastTurnID: "latest",
				baselineRevision: 1
			)
		}
		#expect(runtime.state.generation > initialGeneration)
		#expect(runtime.state.lastTurnID == "latest")
		let pendingBindingGeneration = runtime.state.generation
		try await waitForFailure(runtime)
		{
			runtime.updateContext(
				lastTurnID: "latest",
				baselineRevision: 2
			)
		}
		#expect(runtime.state.generation > pendingBindingGeneration)
		let finishedGeneration = runtime.state.generation
		runtime.updateContext(
			lastTurnID: "latest",
			baselineRevision: 2
		)
		runtime.refreshIfNeeded()
		#expect(runtime.state.generation == finishedGeneration)
		try await waitForFailure(runtime)
		{
			runtime.selectScope(.uncommitted)
		}
		let otherScopeGeneration = runtime.state.generation
		runtime.updateContext(
			lastTurnID: "next",
			baselineRevision: 3
		)
		#expect(runtime.state.generation == otherScopeGeneration)
		runtime.close()
	}

	@MainActor
	private func waitForFailure(
		_ runtime: GitReviewRuntime,
		perform: () -> Void
	) async throws
	{
		perform()
		try await waitForReview(in: runtime)
		{
			runtime.state.pendingRequest == nil && runtime.state.failure != nil
		}
	}

	@MainActor
	private func waitForReview(
		in runtime: GitReviewRuntime,
		_ condition: @escaping () -> Bool
	) async throws
	{
		try Task.checkCancellation()
		guard !condition()
		else
		{
			return
		}
		let previousChange = runtime.onChange
		let checkpoint = AsyncStream<Void>.makeStream()
		defer
		{
			runtime.onChange = previousChange
			checkpoint.continuation.finish()
		}
		runtime.onChange =
		{
			state in
			previousChange?(state)
			if condition()
			{
				checkpoint.continuation.yield(())
				checkpoint.continuation.finish()
			}
		}
		for await _ in checkpoint.stream
		{
			break
		}
		try Task.checkCancellation()
	}

	private func snapshot(
		_ request: GitComparisonRequest,
		id: String = "snapshot"
	)
		-> GitComparisonSnapshot
	{
		let bytes = Data("diff --git a/src/Example.swift b/src/Example.swift\n".utf8)
		return GitComparisonSnapshot(
			request: request,
			id: id,
			resolvedBase: "base",
			resolvedTarget: "target",
			patch: bytes,
			files: [GitComparisonFile(
				oldPath: "src/Example.swift",
				newPath: "src/Example.swift",
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: "",
				hunks: []
			)]
		)
	}

	private func owner(_ thread: String = "thread") -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: "/neutral",
				threads: [],
				selectedThreadID: thread,
				entries: [],
				canLoadEarlierTurns: false,
				changedFiles: [],
				diff: "",
				draft: "",
				canSend: false,
				accountDescription: "Test",
				backendDescription: "Test",
				executionState: .ready,
				statusMessage: nil,
				models: [],
				selectedModelID: nil,
				selectedEffort: nil,
				pendingInteractions: [],
				recentProjects: []
			),
			storeIdentity: "test"
		)
	}
}

private struct MissingRevisionComparisonService: GitComparisonService
{
	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		.unavailable(.invalidRevision("missing-review-revision"))
	}
}

private actor ControlledReviewComparisonService: GitComparisonService
{
	private var requests: [Int: GitComparisonRequest] = [:]
	private var readyRequests: Set<Int> = []
	private var onReadStarted: (@MainActor @Sendable () -> Void)?
	private var isTearingDown = false
	private var requestWaiters: [Int: [UUID: AsyncStream<GitComparisonRequest>.Continuation]] = [:]
	private var continuations: [Int: CheckedContinuation<GitComparisonResult, Never>] = [:]

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		guard !isTearingDown
		else
		{
			return .unavailable(.repositoryChanged)
		}
		return await withCheckedContinuation
		{
			continuation in
			requests[request.generation] = request
			continuations[request.generation] = continuation
			Task
			{
				await onReadStarted?()
				readyRequests.insert(request.generation)
				for waiter in (requestWaiters.removeValue(forKey: request.generation) ?? [:]).values
				{
					waiter.yield(request)
					waiter.finish()
				}
			}
		}
	}

	// Request arrival is a mock checkpoint, not a deadline for main-actor scheduling.
	func request(generation: Int) async throws -> GitComparisonRequest
	{
		try Task.checkCancellation()
		if readyRequests.contains(generation), let request = requests[generation]
		{
			return request
		}
		let id = UUID()
		let checkpoint = AsyncStream<GitComparisonRequest>.makeStream()
		requestWaiters[generation, default: [:]][id] = checkpoint.continuation
		defer
		{
			requestWaiters[generation]?.removeValue(forKey: id)
			if requestWaiters[generation]?.isEmpty == true
			{
				requestWaiters.removeValue(forKey: generation)
			}
			checkpoint.continuation.finish()
		}
		for await request in checkpoint.stream
		{
			try Task.checkCancellation()
			return request
		}
		throw CancellationError()
	}

	func finish(
		generation: Int,
		result: GitComparisonResult
	)
	{
		continuations.removeValue(forKey: generation)?.resume(returning: result)
	}

	func observeReadStarts(_ callback: @escaping @MainActor @Sendable () -> Void)
	{
		onReadStarted = callback
	}

	// Teardown alone releases these responses; scenario cancellation still leaves them pending.
	func releasePendingReads()
	{
		isTearingDown = true
		onReadStarted = nil
		let pending = Array(continuations.values)
		continuations.removeAll()
		for continuation in pending
		{
			continuation.resume(returning: .unavailable(.repositoryChanged))
		}
	}

}
