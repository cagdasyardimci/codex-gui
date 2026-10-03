import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitSummaryBackgroundLoaderTests
{
	@Test func selectionAndCancellationDoNotPublishWindowCallbacks() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
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
		loader.cancel()
		#expect(published.count == 1)
		#expect(loader.projection == nil)
		await service.finish(
			at: 0,
			result: .snapshot(makeSnapshot(request))
		)
		#expect(loader.projection == nil)
		#expect(published.count == 1)
	}

	@Test func refreshRejectsEarlierResultForSameOwner() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		let owner = makeOwner("first")
		loader.select(owner)
		loader.loadIfNeeded(for: owner)
		let old = try await service.request(at: 0)
		loader.refresh(for: owner)
		let current = try await service.request(at: 1)
		#expect(current.generation > old.generation)
		await service.finish(
			at: 0,
			result: .snapshot(makeSnapshot(old))
		)
		#expect(loader.projection?.totals.value == nil)
		await service.finish(
			at: 1,
			result: .snapshot(makeSnapshot(current))
		)
		try await waitUntil
		{
			loader.projection?.totals.value?.additions == 1_943
		}
		#expect(loader.projection?.revision == 4)
	}

	@Test func loadsUncommittedTotalsOnceForSelectedOwner() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
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
		try await waitUntil
		{
			loader.projection?.totals.value == SummaryChangeTotals(
				additions: 1_943,
				deletions: 14
			)
		}
		loader.loadIfNeeded(for: owner)
		#expect(await service.count == 1)
	}

	@Test func lateResultCannotReplaceNewOwner() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		let first = makeOwner("first")
		let second = makeOwner("second")
		loader.select(first)
		loader.loadIfNeeded(for: first)
		let oldRequest = try await service.request(at: 0)
		loader.select(second)
		loader.loadIfNeeded(for: second)
		let currentRequest = try await service.request(at: 1)
		await service.finish(
			at: 0,
			result: .snapshot(makeSnapshot(oldRequest))
		)
		await service.finish(
			at: 1,
			result: .snapshot(makeSnapshot(currentRequest))
		)
		try await waitUntil
		{
			loader.projection?.owner == second && loader.projection?.totals.value != nil
		}
		#expect(loader.projection?.owner == second)
		#expect(loader.projection?.comparisonID == "snapshot-second")
	}

	@Test func revealRefreshKeepsPreviousTotalsAndCanRetryFailure() async throws
	{
		let service = ControlledComparisonService()
		let loader = GitSummaryBackgroundLoader(service: service)
		let owner = makeOwner("first")
		loader.select(owner)
		loader.loadIfNeeded(for: owner)
		let first = try await service.request(at: 0)
		await service.finish(
			at: 0,
			result: .snapshot(makeSnapshot(first))
		)
		try await waitUntil
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
		try await waitUntil
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
		try await waitUntil
		{
			if case .available? = loader.projection?.totals
			{
				return true
			}
			return false
		}
		#expect(await service.count == 3)
	}

	private func makeSnapshot(_ request: GitComparisonRequest) -> GitComparisonSnapshot
	{
		GitComparisonSnapshot(
			request: request,
			id: "snapshot-\(request.owner.selectedThreadID ?? "none")",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(),
			files: [GitComparisonFile(
				oldPath: "file.swift",
				newPath: "file.swift",
				kind: .modified,
				additions: 1_943,
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

	private func waitUntil(_ condition: () -> Bool) async throws
	{
		for _ in 0 ..< 100
		{
			if condition()
			{
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		Issue.record("Timed out waiting for Git summary result")
	}
}

private actor ControlledComparisonService: GitComparisonService
{
	private var requests: [GitComparisonRequest] = []
	private var continuations: [CheckedContinuation<GitComparisonResult, Never>] = []

	var count: Int
	{
		requests.count
	}

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		await withCheckedContinuation
		{
			continuation in
			requests.append(request)
			continuations.append(continuation)
		}
	}

	func request(at index: Int) async throws -> GitComparisonRequest
	{
		for _ in 0 ..< 100
		{
			if requests.indices.contains(index)
			{
				return requests[index]
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		throw TimeoutError()
	}

	func finish(
		at index: Int,
		result: GitComparisonResult
	)
	{
		continuations[index].resume(returning: result)
	}

	private struct TimeoutError: Error
	{
	}
}
