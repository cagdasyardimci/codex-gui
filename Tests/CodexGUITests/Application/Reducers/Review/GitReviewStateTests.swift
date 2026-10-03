import Foundation
import Testing

@testable import CodexGUI

struct GitReviewStateTests
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

	@Test func reducerKeepsPresentationChoicesOutOfComparisonReads() throws
	{
		var state = GitReviewState()
		let activation = GitReviewReducer.reduce(
			state: &state,
			action: .activate(
				owner: owner(),
				lastTurnID: nil,
				baselineRevision: 0,
				baselineFailure: nil
			),
			automaticRefreshEnabled: false
		)
		#expect(activation.publishes)
		let request = try #require(state.pendingRequest)
		let accepted = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(request)),
				request: request
			),
			automaticRefreshEnabled: false
		)
		#expect(accepted.publishes)
		let generation = state.generation
		let originalSummary = state.summary
		for action in [
			GitReviewAction.setFilter("no matches"),
			.expandGap("gap"),
			.toggleDirectory("src"),
			.selectFile("src/Example.swift")
		]
		{
			let transition = GitReviewReducer.reduce(
				state: &state,
				action: action,
				automaticRefreshEnabled: false
			)
			#expect(transition.publishes)
			#expect(transition.effects.isEmpty)
		}
		#expect(state.generation == generation)
		#expect(state.summary == originalSummary)
		#expect(state.pendingRequest == nil)
	}

	@Test func reducerRejectsLateReadAfterScopeChangeAndClose() throws
	{
		var state = GitReviewState()
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .activate(
				owner: owner(),
				lastTurnID: nil,
				baselineRevision: 0,
				baselineFailure: nil
			),
			automaticRefreshEnabled: false
		)
		let old = try #require(state.pendingRequest)
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .selectScope(.staged),
			automaticRefreshEnabled: false
		)
		let staged = try #require(state.pendingRequest)
		let late = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(old)),
				request: old
			),
			automaticRefreshEnabled: false
		)
		#expect(!late.publishes)
		#expect(state.pendingRequest == staged)
		_ = GitReviewReducer.reduce(
			state: &state,
			action: .close,
			automaticRefreshEnabled: false
		)
		let closed = GitReviewReducer.reduce(
			state: &state,
			action: .received(
				.snapshot(snapshot(staged)),
				request: staged
			),
			automaticRefreshEnabled: false
		)
		#expect(!closed.publishes)
		#expect(state.snapshot == nil)
	}

	@Test func ownerScopeGenerationAndCloseRejectLateResults() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		state.scope = .staged
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedRetiredRequest = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(!acceptedRetiredRequest)
		let acceptedCurrentRequest = state.accept(
			.snapshot(snapshot(second)),
			request: second
		)
		#expect(acceptedCurrentRequest)
		state.activate(owner: owner("another"))
		let acceptedForeignOwnerRequest = state.accept(
			.snapshot(snapshot(second)),
			request: second
		)
		#expect(!acceptedForeignOwnerRequest)
		let thirdOptional = state.beginRequest()
		let third = try #require(thirdOptional)
		state.close()
		let acceptedClosedRequest = state.accept(
			.snapshot(snapshot(third)),
			request: third
		)
		#expect(!acceptedClosedRequest)
		#expect(state.snapshot == nil)
	}

	@Test func reopenedSameOwnerRejectsPreviousLifetime() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let oldOptional = state.beginRequest()
		let old = try #require(oldOptional)
		state.close()
		state.activate(owner: owner())
		let currentOptional = state.beginRequest()
		let current = try #require(currentOptional)
		#expect(old.generation < current.generation)
		let acceptedPreviousLifetime = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(!acceptedPreviousLifetime)
		#expect(state.pendingRequest == current)
	}

	@Test func filtersKeepRawSummaryAndStaleCopiesAreDisabled() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let requestOptional = state.beginRequest()
		let request = try #require(requestOptional)
		let acceptedInitialSnapshot = state.accept(
			.snapshot(snapshot(request)),
			request: request
		)
		#expect(acceptedInitialSnapshot)
		state.filter = "no matches"
		state.options.ignoreImports = true
		#expect(state.summary == .available(SummaryChangeTotals(
			additions: 1,
			deletions: 1
		)))
		#expect(state.copyCommand != nil)
		let replacementOptional = state.beginRequest()
		let replacement = try #require(replacementOptional)
		#expect(state.isStale)
		#expect(state.copyCommand == nil)
		let acceptedReplacementFailure = state.accept(
			.unavailable(.repositoryChanged),
			request: replacement
		)
		#expect(acceptedReplacementFailure)
		#expect(state.snapshot != nil)
		#expect(state.copyCommand == nil)
	}

	@Test func unchangedRefreshPreservesSnapshotContextIdentity() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		let acceptedFirstSnapshot = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(acceptedFirstSnapshot)
		state.options.expandedGapIDs = ["gap"]
		state.expandedDirectories.removeAll()
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedUnchangedSnapshot = state.accept(
			.snapshot(snapshot(
				second,
				id: "new"
			)),
			request: second
		)
		#expect(acceptedUnchangedSnapshot)
		#expect(state.snapshot?.id == "snapshot")
		#expect(state.options.expandedGapIDs == ["gap"])
		#expect(state.expandedDirectories.isEmpty)
	}

	@Test func mismatchedSnapshotDoesNotConsumePendingRequest() throws
	{
		var state = GitReviewState()
		state.activate(owner: owner())
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		let secondOptional = state.beginRequest()
		let second = try #require(secondOptional)
		let acceptedMismatchedSnapshot = state.accept(
			.snapshot(snapshot(first)),
			request: second
		)
		#expect(!acceptedMismatchedSnapshot)
		#expect(state.pendingRequest == second)
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

	@Test func latestTurnAndCapturePublicationInvalidateOnlyLastTurnRequests() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "old",
			baselineRevision: 1
		)
		state.scope = .lastTurn
		let oldOptional = state.beginRequest()
		let old = try #require(oldOptional)
		#expect(old.lastTurnID == "old")
		let turnContextResult1 = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(turnContextResult1)
		let turnContextResult2 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 1
		)
		#expect(turnContextResult2)
		#expect(state.isStale)
		#expect(state.copyCommand == nil)
		let currentOptional = state.beginRequest()
		let current = try #require(currentOptional)
		#expect(current.lastTurnID == "new")
		let turnContextResult3 = state.accept(
			.snapshot(snapshot(old)),
			request: old
		)
		#expect(!turnContextResult3)
		let turnContextResult4 = state.accept(
			.unavailable(.lastTurnUnavailable),
			request: current
		)
		#expect(turnContextResult4)
		let failedGeneration = state.generation
		let turnContextResult5 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 1
		)
		#expect(!turnContextResult5)
		#expect(state.generation == failedGeneration)
		let turnContextResult6 = state.updateTurnContext(
			lastTurnID: "new",
			baselineRevision: 2
		)
		#expect(turnContextResult6)
		let afterBindingOptional = state.beginRequest()
		let afterBinding = try #require(afterBindingOptional)
		#expect(afterBinding.lastTurnID == "new")
		#expect(afterBinding.generation > failedGeneration)
		state.scope = .uncommitted
		let uncommittedOptional = state.beginRequest()
		let uncommitted = try #require(uncommittedOptional)
		#expect(uncommitted.lastTurnID == nil)
		let turnContextResult7 = state.updateTurnContext(
			lastTurnID: "later",
			baselineRevision: 3
		)
		#expect(!turnContextResult7)
		#expect(state.pendingRequest == uncommitted)
	}

	@Test func latestTurnContextResetsOnOwnerChangeAndClose() throws
	{
		var state = GitReviewState()
		state.activate(
			owner: owner(),
			lastTurnID: "first-turn",
			baselineRevision: 4
		)
		state.scope = .lastTurn
		let firstOptional = state.beginRequest()
		let first = try #require(firstOptional)
		state.activate(
			owner: owner("another"),
			lastTurnID: "other-turn",
			baselineRevision: 1
		)
		state.scope = .lastTurn
		let otherOptional = state.beginRequest()
		let other = try #require(otherOptional)
		#expect(other.lastTurnID == "other-turn")
		let turnContextResult8 = state.accept(
			.snapshot(snapshot(first)),
			request: first
		)
		#expect(!turnContextResult8)
		state.close()
		#expect(state.lastTurnID == nil)
		#expect(state.baselineRevision == 0)
	}

	@Test @MainActor
	func matchingCaptureFailureRetainsItsPreciseUnavailableReason() async
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
		#expect(runtime.state.failure == captureFailure)
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
