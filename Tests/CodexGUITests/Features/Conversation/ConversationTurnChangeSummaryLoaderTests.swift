import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
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
		let first = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		let firstComposer = ConversationPresentation(first).composer
		loader.render(firstComposer)
		await service.waitForRequestCount(1)
		loader.render(firstComposer)
		#expect(await service.requestCount == 1)

		var second = ConversationTurnChangeSummaryTestFixture.makeSnapshot(
			selectedThreadID: "second-task"
		)
		second.activeThreadID = "second-task"
		second.reportedGitChanges = []
		loader.render(ConversationPresentation(second).composer)
		await service.waitForRequestCount(2)
		await service.complete(1)
		for _ in 0 ..< 100 where observed != nil
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed == nil)
		await service.complete(0)
		await Task.yield()
		#expect(observed == nil)
		loader.stop()
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
		var previous = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		previous.reportedGitTurnID = "previous"
		loader.render(ConversationPresentation(previous).composer)
		await service.waitForRequestCount(1)
		await service.complete(0)
		for _ in 0 ..< 100 where observed?.usesPreviousTurn != true
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed?.usesPreviousTurn == true)
		#expect(observed?.additions == 3)
		var active = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		loader.render(ConversationPresentation(active).composer)
		await service.waitForRequestCount(2)
		await service.complete(1)
		for _ in 0 ..< 100 where observed?.usesPreviousTurn != false || observed?.isLoading == true
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed?.usesPreviousTurn == false)
		#expect(observed?.additions == 3)
		active.reportedGitChanges = []
		loader.render(ConversationPresentation(active).composer)
		await service.waitForRequestCount(3)
		await service.complete(2)
		for _ in 0 ..< 100 where observed != nil
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed == nil)
		loader.stop()
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
		loader.render(ConversationPresentation(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		).composer)
		await service.waitForRequestCount(1)
		await service.complete(
			0,
			result: .unavailable(.oversized)
		)
		for _ in 0 ..< 100 where observed?.isLoading != false
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		let button = TurnChangeSummaryButton()
		button.render(observed)
		#expect(button.attributedTitle.string == "2 files changed +3 -1")
		loader.stop()
	}

	@Test func reportsArrivingAfterZeroCountsRefreshTheBadge() async throws
	{
		let loader = ConversationTurnChangeSummaryLoader()
		var observed: ConversationTurnChangeSummary?
		loader.onChange =
		{
			observed = $0
		}
		loader.render(ConversationPresentation(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot(reports: false)
		).composer)
		#expect(observed?.failure == .lastTurnUnavailable)
		let button = TurnChangeSummaryButton()
		button.render(observed)
		#expect(button.attributedTitle.string == "0 files changed +0 -0")
		loader.render(ConversationPresentation(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		).composer)
		for _ in 0 ..< 100 where observed?.additions != 3
		{
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(observed?.fileCount == 2)
		#expect(observed?.additions == 3)
		#expect(observed?.failure == nil)
		loader.stop()
		#expect(observed == nil)
	}
}

private actor TurnChangeSummaryServiceStub: GitComparisonService
{
	private var requests: [GitComparisonRequest] = []
	private var completions: [Int: CheckedContinuation<GitComparisonResult, Never>] = [:]
	private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
	var requestCount: Int
	{
		requests.count
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let index = requests.count
		requests.append(request)
		return await withCheckedContinuation
		{
			completions[index] = $0
			let ready = waiters.filter
			{
				$0.0 <= requests.count
			}
			waiters.removeAll
			{
				$0.0 <= requests.count
			}
			for waiter in ready
			{
				waiter.1.resume()
			}
		}
	}

	func waitForRequestCount(_ count: Int) async
	{
		guard requests.count < count
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters.append((count, $0))
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
}
