import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ProjectFileIndexRuntimeTests
{
	@Test func samePathOwnerCycleRejectsFirstRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(service: service)
		let first = makeOwner(
			path: "/fixture",
			thread: "first"
		)
		let second = makeOwner(
			path: "/fixture",
			thread: "second"
		)
		runtime.select(first)
		_ = try await service.path(at: 0)
		runtime.select(second)
		_ = try await service.path(at: 1)
		runtime.select(first)
		_ = try await service.path(at: 2)
		#expect(runtime.index == nil)
		try await waitUntil
		{
			await service.wasCancelled(at: 0)
		}
		try await waitUntil
		{
			await service.wasCancelled(at: 1)
		}
		await service.finish(
			at: 0,
			files: ["stale.swift"]
		)
		await service.finish(
			at: 1,
			files: ["other.swift"]
		)
		await service.finish(
			at: 2,
			files: ["current.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["current.swift"]
		}
	}

	@Test func clearAndShutdownCancelPendingEnumeration() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(service: service)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		runtime.select(makeOwner(
			path: nil,
			thread: "first"
		))
		try await waitUntil
		{
			await service.wasCancelled(at: 0)
		}
		await service.finish(
			at: 0,
			files: ["stale.swift"]
		)
		#expect(runtime.index == nil)

		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		_ = try await service.path(at: 1)
		runtime.shutdown()
		try await waitUntil
		{
			await service.wasCancelled(at: 1)
		}
		await service.finish(
			at: 1,
			files: ["late.swift"]
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "third"
		))
		#expect(runtime.index == nil)
		#expect(await service.count == 2)
	}

	@Test func observerSelectionReplacesPendingRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(service: service)
		let next = makeOwner(
			path: "/next",
			thread: "next"
		)
		var notifications = 0
		runtime.onChange =
		{
			[weak runtime] in
			notifications += 1
			if notifications == 1
			{
				runtime?.select(next)
			}
		}
		runtime.select(makeOwner(
			path: "/first",
			thread: "first"
		))
		let requestedPath = try await service.path(at: 0)
		#expect(requestedPath == "/next")
		await service.finish(
			at: 0,
			files: ["next.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["next.swift"]
		}
		#expect(await service.count == 1)
	}

	@Test func observerShutdownPreventsPendingRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(service: service)
		runtime.onChange =
		{
			[weak runtime] in
			runtime?.shutdown()
		}
		runtime.select(makeOwner(
			path: "/first",
			thread: "first"
		))
		try await Task.sleep(for: .milliseconds(10))
		#expect(runtime.index == nil)
		#expect(await service.count == 0)
	}

	private func makeOwner(
		path: String?,
		thread: String
	) -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			ConversationSnapshot(
				projectPath: path,
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

	private func waitUntil(_ condition: () async -> Bool) async throws
	{
		for _ in 0 ..< 100
		{
			if await condition()
			{
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		Issue.record("Timed out waiting for file index")
	}
}

private actor ControlledProjectFileIndexService: ProjectFileIndexService
{
	private var paths: [String] = []
	private var continuations: [CheckedContinuation<ProjectFileIndex?, Never>] = []
	private var cancelled: Set<Int> = []

	var count: Int
	{
		paths.count
	}

	func load(projectPath: String) async -> ProjectFileIndex?
	{
		let index = paths.count
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				paths.append(projectPath)
				continuations.append(continuation)
			}
		} onCancel:
		{
			Task
			{
				await self.markCancelled(index)
			}
		}
	}

	func path(at index: Int) async throws -> String
	{
		for _ in 0 ..< 100
		{
			if paths.indices.contains(index)
			{
				return paths[index]
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		throw TimeoutError()
	}

	func wasCancelled(at index: Int) -> Bool
	{
		cancelled.contains(index)
	}

	func finish(
		at index: Int,
		files: [String]
	)
	{
		continuations[index].resume(returning: ProjectFileIndex(files: files))
	}

	private func markCancelled(_ index: Int)
	{
		cancelled.insert(index)
	}

	private struct TimeoutError: Error
	{
	}
}
