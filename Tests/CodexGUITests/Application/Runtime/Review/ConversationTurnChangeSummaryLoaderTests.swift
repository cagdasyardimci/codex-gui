import Foundation
import Testing

@testable import CodexGUI

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ConversationTurnChangeSummaryLoaderTests
{

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
