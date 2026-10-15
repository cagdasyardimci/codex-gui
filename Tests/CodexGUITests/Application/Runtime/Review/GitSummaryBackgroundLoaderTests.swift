import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1))) @MainActor
struct GitSummaryBackgroundLoaderTests
{
	@Test func selectionAndCancellationDoNotPublishWindowCallbacks() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				loader.readTask
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				loader.cancel()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let owner = makeOwner("first")
			var published: [GitReviewSummaryProjection?] = []
			loader.onChange =
			{
				published.append($0)
			}
			loader.select(owner)
			#expect(published.isEmpty)
			loader.loadIfNeeded(for: owner)
			#expect(published.count == 1)
			#expect(loader.projection?.owner == owner)
			let request = try await service.request(at: 0)
			let canceledRead = try #require(loader.readTask)
			loader.cancel()
			#expect(published.count == 1)
			#expect(loader.projection == nil)
			await service.finish(
				at: 0,
				result: .snapshot(makeSnapshot(request))
			)
			await canceledRead.value
			#expect(loader.projection == nil)
			#expect(published.count == 1)
		}
	}

	@Test(arguments: [false, true])
	func refreshRejectsEarlierResultForSameOwner(lateAfterCurrent: Bool) async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				loader.readTask
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				loader.cancel()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let owner = makeOwner("first")
			var publications = 0
			loader.onChange =
			{
				_ in publications += 1
			}
			loader.select(owner)
			loader.loadIfNeeded(for: owner)
			let old = try await service.request(at: 0)
			let obsoleteRead = try #require(loader.readTask)
			loader.refresh(for: owner)
			let current = try await service.request(at: 1)
			let currentRead = try #require(loader.readTask)
			#expect(current.generation > old.generation)
			if lateAfterCurrent
			{
				await service.finish(
					at: 1,
					result: .snapshot(makeSnapshot(
						current,
						id: "current"
					))
				)
				await currentRead.value
				#expect(loader.projection?.comparisonID == "current")
			}
			let publicationsBeforeObsoleteResult = publications
			await service.finish(
				at: 0,
				result: .snapshot(makeSnapshot(
					old,
					id: "obsolete",
					additions: 7
				))
			)
			await obsoleteRead.value
			#expect(publications == publicationsBeforeObsoleteResult)
			#expect(loader.projection?.comparisonID == (lateAfterCurrent ? "current" : nil))
			if !lateAfterCurrent
			{
				#expect(loader.projection?.totals.value == nil)
				await service.finish(
					at: 1,
					result: .snapshot(makeSnapshot(
						current,
						id: "current"
					))
				)
				await currentRead.value
			}
			#expect(loader.projection?.totals.value == SummaryChangeTotals(
				additions: 1_943,
				deletions: 14
			))
			#expect(loader.projection?.comparisonID == "current")
			#expect(loader.projection?.revision == 4)
		}
	}

	@Test func loadsUncommittedTotalsOnceForSelectedOwner() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				loader.readTask
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				loader.cancel()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let owner = makeOwner("first")
			loader.select(owner)
			loader.loadIfNeeded(for: owner)
			loader.loadIfNeeded(for: owner)
			let request = try await service.request(at: 0)
			#expect(request.scope == .uncommitted)
			#expect(request.owner == owner)
			await service.finish(
				at: 0,
				result: .snapshot(makeSnapshot(request))
			)
			try await waitForProjection(in: loader)
			{
				loader.projection?.totals.value == SummaryChangeTotals(
					additions: 1_943,
					deletions: 14
				)
			}
			loader.loadIfNeeded(for: owner)
			#expect(await service.count == 1)
		}
	}

	@Test(arguments: [false, true])
	func lateResultCannotReplaceNewOwner(lateAfterCurrent: Bool) async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				loader.readTask
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				loader.cancel()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let first = makeOwner("first")
			let second = makeOwner("second")
			var publications = 0
			loader.onChange =
			{
				_ in publications += 1
			}
			loader.select(first)
			loader.loadIfNeeded(for: first)
			let oldRequest = try await service.request(at: 0)
			let obsoleteRead = try #require(loader.readTask)
			loader.select(second)
			loader.loadIfNeeded(for: second)
			let currentRequest = try await service.request(at: 1)
			let currentRead = try #require(loader.readTask)
			if lateAfterCurrent
			{
				await service.finish(
					at: 1,
					result: .snapshot(makeSnapshot(currentRequest))
				)
				await currentRead.value
				#expect(loader.projection?.comparisonID == "snapshot-second")
			}
			let publicationsBeforeObsoleteResult = publications
			await service.finish(
				at: 0,
				result: .snapshot(makeSnapshot(oldRequest))
			)
			await obsoleteRead.value
			#expect(publications == publicationsBeforeObsoleteResult)
			#expect(loader.projection?.owner == second)
			#expect(loader.projection?.comparisonID == (lateAfterCurrent ? "snapshot-second" : nil))
			if !lateAfterCurrent
			{
				await service.finish(
					at: 1,
					result: .snapshot(makeSnapshot(currentRequest))
				)
				await currentRead.value
			}
			#expect(loader.projection?.owner == second)
			#expect(loader.projection?.comparisonID == "snapshot-second")
			#expect(loader.projection?.totals.value == SummaryChangeTotals(
				additions: 1_943,
				deletions: 14
			))
		}
	}

	@Test func revealRefreshKeepsPreviousTotalsAndCanRetryFailure() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				loader.readTask
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				loader.cancel()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let owner = makeOwner("first")
			loader.select(owner)
			loader.loadIfNeeded(for: owner)
			let first = try await service.request(at: 0)
			await service.finish(
				at: 0,
				result: .snapshot(makeSnapshot(first))
			)
			try await waitForProjection(in: loader)
			{
				loader.projection?.totals.value?.additions == 1_943
			}
			let priorID = loader.projection?.comparisonID
			loader.refresh(for: owner)
			#expect(loader.projection?.totals.value?.additions == 1_943)
			#expect(loader.projection?.comparisonID == priorID)
			_ = try await service.request(at: 1)
			await service.finish(
				at: 1,
				result: .unavailable(.repositoryChanged)
			)
			try await waitForProjection(in: loader)
			{
				if case .failed? = loader.projection?.totals
				{
					return true
				}
				return false
			}
			#expect(loader.projection?.totals.value?.additions == 1_943)
			loader.refresh(for: owner)
			let retry = try await service.request(at: 2)
			await service.finish(
				at: 2,
				result: .snapshot(makeSnapshot(retry))
			)
			try await waitForProjection(in: loader)
			{
				if case .available? = loader.projection?.totals
				{
					return true
				}
				return false
			}
			#expect(await service.count == 3)
		}
	}

	private func makeSnapshot(
		_ request: GitComparisonRequest,
		id: String? = nil,
		additions: Int = 1_943
	) -> GitComparisonSnapshot
	{
		GitComparisonSnapshot(
			request: request,
			id: id ?? "snapshot-\(request.owner.selectedThreadID ?? "none")",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(),
			files: [GitComparisonFile(
				oldPath: "file.swift",
				newPath: "file.swift",
				kind: .modified,
				additions: additions,
				deletions: 14,
				isBinary: false,
				patch: "",
				hunks: []
			)]
		)
	}

	private func makeOwner(_ thread: String) -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: "/fixture",
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

	// Observe publication rather than assuming the shared actor runs within a polling deadline.
	private func waitForProjection(
		in loader: GitSummaryBackgroundLoader,
		_ condition: @escaping () -> Bool
	) async throws
	{
		try Task.checkCancellation()
		guard !condition()
		else
		{
			return
		}
		let previousChange = loader.onChange
		let checkpoint = AsyncStream<Void>.makeStream()
		defer
		{
			loader.onChange = previousChange
			checkpoint.continuation.finish()
		}
		loader.onChange =
		{
			projection in
			previousChange?(projection)
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
}

private actor ControlledComparisonService: GitComparisonService
{
	private var requests: [GitComparisonRequest] = []
	private var readyRequests: Set<Int> = []
	private var onReadStarted: (@MainActor @Sendable () -> Void)?
	private var isTearingDown = false
	private var requestWaiters: [Int: [UUID: AsyncStream<GitComparisonRequest>.Continuation]] = [:]
	private var continuations: [Int: CheckedContinuation<GitComparisonResult, Never>] = [:]

	var count: Int
	{
		requests.count
	}

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
			let index = requests.count
			requests.append(request)
			continuations[index] = continuation
			Task
			{
				await onReadStarted?()
				readyRequests.insert(index)
				for waiter in (requestWaiters.removeValue(forKey: index) ?? [:]).values
				{
					waiter.yield(request)
					waiter.finish()
				}
			}
		}
	}

	func request(at index: Int) async throws -> GitComparisonRequest
	{
		try Task.checkCancellation()
		if readyRequests.contains(index)
		{
			return requests[index]
		}
		let id = UUID()
		let checkpoint = AsyncStream<GitComparisonRequest>.makeStream()
		requestWaiters[index, default: [:]][id] = checkpoint.continuation
		defer
		{
			requestWaiters[index]?.removeValue(forKey: id)
			if requestWaiters[index]?.isEmpty == true
			{
				requestWaiters.removeValue(forKey: index)
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
		at index: Int,
		result: GitComparisonResult
	)
	{
		continuations.removeValue(forKey: index)!.resume(returning: result)
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
