import Foundation
import Testing

@testable import CodexGUI

struct GitReviewRuntimeTests
{
	@Test @MainActor
	func reentrantReloadDuringLoadingKeepsNewestRead() async throws
	{
		let service = ControlledReviewComparisonService()
		let runtime = GitReviewRuntime(service: service)
		runtime.activate(owner: owner())
		let first = try #require(runtime.state.pendingRequest)
		_ = try await service.request(generation: first.generation)
		var didReenter = false
		runtime.onChange =
		{
			state in
			if state.pendingRequest?.generation == first.generation + 1,
				!didReenter
			{
				didReenter = true
				runtime.reload()
			}
		}
		runtime.reload()
		let latest = try #require(runtime.state.pendingRequest)
		#expect(didReenter)
		#expect(latest.generation == first.generation + 2)
		_ = try await service.request(generation: latest.generation)
		await service.finish(
			generation: first.generation,
			result: .snapshot(snapshot(first))
		)
		await service.finish(
			generation: latest.generation,
			result: .snapshot(snapshot(latest))
		)
		try await waitForReview
		{
			runtime.state.snapshot?.request == latest
		}
		#expect(runtime.state.snapshot?.request == latest)
		runtime.close()
	}

	@Test @MainActor
	func reentrantCloseDuringLoadingInvalidatesActiveRead() async throws
	{
		let service = ControlledReviewComparisonService()
		let runtime = GitReviewRuntime(service: service)
		runtime.activate(owner: owner())
		let first = try #require(runtime.state.pendingRequest)
		_ = try await service.request(generation: first.generation)
		var didClose = false
		runtime.onChange =
		{
			state in
			if state.pendingRequest?.generation == first.generation + 1,
				!didClose
			{
				didClose = true
				runtime.close()
			}
		}
		runtime.reload()
		#expect(didClose)
		#expect(!runtime.state.isOpen)
		await service.finish(
			generation: first.generation,
			result: .snapshot(snapshot(first))
		)
		await Task.yield()
		#expect(runtime.state.snapshot == nil)
		#expect(runtime.state.pendingRequest == nil)
	}

	@Test @MainActor
	func failedRuntimePollingKeepsRevisionFailureVisibleUntilExplicitRetry() async
	{
		let runtime = GitReviewRuntime(service: MissingRevisionComparisonService())
		await withCheckedContinuation
		{
			completion in
			runtime.onChange =
			{
				state in
				if state.failure == .invalidRevision("missing-review-revision")
				{
					runtime.onChange = nil
					completion.resume()
				}
			}
			runtime.activate(owner: owner())
		}
		let failedGeneration = runtime.state.generation
		for _ in 0 ..< 3
		{
			runtime.refreshIfNeeded()
		}
		#expect(runtime.state.generation == failedGeneration)
		#expect(runtime.state.pendingRequest == nil)
		#expect(runtime.state.failure == .invalidRevision("missing-review-revision"))
		#expect(runtime.state.copyCommand == nil)
		await withCheckedContinuation
		{
			completion in
			runtime.onChange =
			{
				state in
				if state.failure != nil
				{
					runtime.onChange = nil
					completion.resume()
				}
			}
			runtime.reload()
		}
		#expect(runtime.state.generation > failedGeneration)
		#expect(runtime.state.pendingRequest == nil)
		runtime.close()
	}

	@Test @MainActor
	func lastTurnReportsMissingPayloadInsteadOfAnUnrelatedCaptureFailure() async
	{
		let runtime = GitReviewRuntime(service: MissingRevisionComparisonService())
		let captureFailure = GitComparisonFailure
			.lastTurnBaselineUnavailable("Tracked file capture exceeds the configured limit.")
		await waitForFailure(runtime)
		{
			runtime.activate(
				owner: owner(),
				lastTurnID: "latest",
				baselineRevision: 1,
				baselineFailure: captureFailure
			)
		}
		await waitForFailure(runtime)
		{
			runtime.selectScope(.lastTurn)
		}
		#expect(runtime.state.failure == .lastTurnUnavailable)
		#expect(runtime.state.pendingRequest == nil)
		runtime.close()
	}

	@Test @MainActor
	func turnChangeAndFinishedBindingRetryFailedLastTurnExactlyOnce() async
	{
		let runtime = GitReviewRuntime(
			service: MissingRevisionComparisonService(),
			automaticRefreshEnabled: true
		)
		await waitForFailure(runtime)
		{
			runtime.activate(
				owner: owner(),
				lastTurnID: "first",
				baselineRevision: 1
			)
		}
		await waitForFailure(runtime)
		{
			runtime.selectScope(.lastTurn)
		}
		let initialGeneration = runtime.state.generation
		await waitForFailure(runtime)
		{
			runtime.updateContext(
				lastTurnID: "latest",
				baselineRevision: 1
			)
		}
		#expect(runtime.state.generation > initialGeneration)
		#expect(runtime.state.lastTurnID == "latest")
		let pendingBindingGeneration = runtime.state.generation
		await waitForFailure(runtime)
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
		await waitForFailure(runtime)
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

	@Test @MainActor
	func automaticUpdatesStayDisabledUntilExplicitRefresh() async
	{
		let runtime = GitReviewRuntime(service: MissingRevisionComparisonService())
		#expect(!runtime.automaticRefreshEnabled)
		await waitForFailure(runtime)
		{
			runtime.activate(owner: owner())
		}
		await waitForFailure(runtime)
		{
			runtime.selectScope(.lastTurn)
		}
		var publishedGenerations: [Int] = []
		runtime.onChange =
		{
			publishedGenerations.append($0.generation)
		}
		runtime.updateContext(
			lastTurnID: "next",
			baselineRevision: 1
		)
		#expect(publishedGenerations.count == 1)
		#expect(runtime.state.pendingRequest == nil)
		let generation = runtime.state.generation
		runtime.refreshIfNeeded()
		#expect(runtime.state.generation == generation)
		await waitForFailure(runtime)
		{
			runtime.reload()
		}
		#expect(runtime.state.generation > generation)
		runtime.close()
	}

	@MainActor
	private func waitForFailure(
		_ runtime: GitReviewRuntime,
		perform: () -> Void
	) async
	{
		await withCheckedContinuation
		{
			completion in
			runtime.onChange =
			{
				state in
				if state.failure != nil
				{
					runtime.onChange = nil
					completion.resume()
				}
			}
			perform()
		}
	}

	@MainActor
	private func waitForReview(_ condition: () -> Bool) async throws
	{
		for _ in 0 ..< 100
		{
			if condition()
			{
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		Issue.record("Timed out waiting for Git review result")
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
	private var continuations: [Int: CheckedContinuation<GitComparisonResult, Never>] = [:]

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		await withCheckedContinuation
		{
			continuation in
			requests[request.generation] = request
			continuations[request.generation] = continuation
		}
	}

	func request(generation: Int) async throws -> GitComparisonRequest
	{
		for _ in 0 ..< 100
		{
			if let request = requests[generation]
			{
				return request
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		throw TimeoutError()
	}

	func finish(
		generation: Int,
		result: GitComparisonResult
	)
	{
		continuations.removeValue(forKey: generation)?.resume(returning: result)
	}

	private struct TimeoutError: Error
	{
	}
}
