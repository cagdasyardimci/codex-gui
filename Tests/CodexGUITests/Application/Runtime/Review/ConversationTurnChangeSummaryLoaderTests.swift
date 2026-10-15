import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ConversationTurnChangeSummaryLoaderTests
{
	@Test func unchangedReportsDoNotRereadTheCheckoutAndLateTaskResultsAreIgnored() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
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
				loader.stop()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let first = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
			loader.render(first)
			try await service.waitForRequestCount(1)
			let firstRead = try #require(loader.readTask)
			loader.render(first)
			#expect(await service.requestCount == 1)

			var second = ConversationTurnChangeSummaryTestFixture.makeSnapshot(
				selectedThreadID: "second-task"
			)
			second.activeThreadID = "second-task"
			second.reportedGitChanges = []
			loader.render(second)
			try await service.waitForRequestCount(2)
			await service.complete(1)
			await loader.waitForLoading()
			#expect(observed == nil)
			await service.complete(0)
			// Await the cancelled request itself so the ignored-result assertion is not premature.
			await firstRead.value
			#expect(observed == nil)
		}
	}

	@Test func previousTurnCountsAreReplacedWhenActiveReportsArrive() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
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
				loader.stop()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			var previous = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
			previous.reportedGitTurnID = "previous"
			loader.render(previous)
			try await service.waitForRequestCount(1)
			await service.complete(0)
			await loader.waitForLoading()
			#expect(observed?.usesPreviousTurn == true)
			#expect(observed?.fileCount == 2)
			#expect(observed?.additions == 3)
			#expect(observed?.deletions == 1)
			var active = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
			active.reportedGitChanges = [try #require(FileChange(json: [
				"path": "Sources/Active.swift",
				"kind": "add",
				"diff": "@@ -0,0 +1,5 @@\n+one\n+two\n+three\n+four\n+five",
			]))]
			loader.render(active)
			try await service.waitForRequestCount(2)
			await service.complete(1)
			await loader.waitForLoading()
			#expect(observed?.usesPreviousTurn == false)
			#expect(observed?.fileCount == 1)
			#expect(observed?.additions == 5)
			#expect(observed?.deletions == 0)
			active.reportedGitChanges = []
			loader.render(active)
			try await service.waitForRequestCount(3)
			await service.complete(2)
			await loader.waitForLoading()
			#expect(observed == nil)
		}
	}

	@Test func activeTurnIdentityRefreshesAnOtherwiseUnchangedRequest() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
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
				loader.stop()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
			let request = try #require(snapshot.runningGitReviewRequest(
				owner: FeaturePresentationOwner(snapshot)
			))
			loader.render(
				request: request,
				activeTurnID: "other"
			)
			try await service.waitForRequestCount(1)
			await service.complete(0)
			await loader.waitForLoading()
			#expect(observed?.usesPreviousTurn == true)
			loader.render(
				request: request,
				activeTurnID: request.lastTurnID
			)
			try await service.waitForRequestCount(2)
			await service.complete(1)
			await loader.waitForLoading()
			#expect(observed?.usesPreviousTurn == false)
		}
	}

	@Test func previewFailureUsesReportedCounts() async throws
	{
		let service = TurnChangeSummaryServiceStub()
		let loader = ConversationTurnChangeSummaryLoader(service: service)
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
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
				loader.stop()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			loader.render(ConversationTurnChangeSummaryTestFixture.makeSnapshot())
			try await service.waitForRequestCount(1)
			await service.complete(
				0,
				result: .unavailable(.oversized)
			)
			await loader.waitForLoading()
			let button = TurnChangeSummaryButton()
			button.render(observed)
			#expect(button.attributedTitle.string == "2 files changed +3 -1")
		}
	}

	@Test func reportsArrivingAfterZeroCountsRefreshTheBadge() async throws
	{
		let loader = ConversationTurnChangeSummaryLoader()
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
		loader.render(ConversationTurnChangeSummaryTestFixture.makeSnapshot(reports: false))
		#expect(observed?.failure == .lastTurnUnavailable)
		let button = TurnChangeSummaryButton()
		button.render(observed)
		#expect(button.attributedTitle.string == "0 files changed +0 -0")
		loader.render(ConversationTurnChangeSummaryTestFixture.makeSnapshot())
		await loader.waitForLoading()
		#expect(observed?.fileCount == 2)
		#expect(observed?.additions == 3)
		#expect(observed?.failure == nil)
		loader.stop()
		#expect(observed == nil)
	}
}

private extension ConversationTurnChangeSummaryLoader
{
	func render(_ snapshot: ConversationSnapshot)
	{
		render(
			request: snapshot.runningGitReviewRequest(owner: FeaturePresentationOwner(snapshot)),
			activeTurnID: snapshot.activeTurnID
		)
	}
}

private actor TurnChangeSummaryServiceStub: GitComparisonService
{
	private var requests: [GitComparisonRequest] = []
	private var readyRequests: Set<Int> = []
	private var onReadStarted: (@MainActor @Sendable () -> Void)?
	private var isTearingDown = false
	private var completions: [Int: CheckedContinuation<GitComparisonResult, Never>] = [:]
	private var waiters: [Int: [UUID: AsyncStream<Void>.Continuation]] = [:]
	var requestCount: Int
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
		// Scenario reads deliberately resist cancellation until their response is released.
		return await withCheckedContinuation
		{
			continuation in
			let index = requests.count
			requests.append(request)
			completions[index] = continuation
			Task
			{
				await onReadStarted?()
				readyRequests.insert(index)
				let readyCounts = waiters.keys.filter
				{
					isReady($0)
				}
				for count in readyCounts
				{
					for waiter in (waiters.removeValue(forKey: count) ?? [:]).values
					{
						waiter.yield(())
						waiter.finish()
					}
				}
			}
		}
	}

	func waitForRequestCount(_ count: Int) async throws
	{
		try Task.checkCancellation()
		guard !isReady(count)
		else
		{
			return
		}
		let id = UUID()
		let checkpoint = AsyncStream<Void>.makeStream()
		waiters[count, default: [:]][id] = checkpoint.continuation
		defer
		{
			waiters[count]?.removeValue(forKey: id)
			if waiters[count]?.isEmpty == true
			{
				waiters.removeValue(forKey: count)
			}
			checkpoint.continuation.finish()
		}
		for await _ in checkpoint.stream
		{
			try Task.checkCancellation()
			return
		}
		throw CancellationError()
	}

	private func isReady(_ count: Int) -> Bool
	{
		(0 ..< count).allSatisfy
		{
			readyRequests.contains($0)
		}
	}

	func complete(
		_ index: Int,
		result: GitComparisonResult? = nil
	)
	{
		completions.removeValue(forKey: index)?.resume(
			returning: result ?? GitReportedTurnComparison.compare(requests[index])
		)
	}

	func observeReadStarts(_ callback: @escaping @MainActor @Sendable () -> Void)
	{
		onReadStarted = callback
	}

	// Teardown releases every pending read; normal cancellation keeps late responses testable.
	func releasePendingReads()
	{
		isTearingDown = true
		onReadStarted = nil
		let pending = Array(completions.values)
		completions.removeAll()
		for continuation in pending
		{
			continuation.resume(returning: .unavailable(.repositoryChanged))
		}
		for waiter in waiters.values.flatMap(
			{
				$0.values
			}
		)
		{
			waiter.finish()
		}
		waiters.removeAll()
	}
}
