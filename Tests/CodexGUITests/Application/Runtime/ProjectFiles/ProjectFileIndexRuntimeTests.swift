import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ProjectFileIndexRuntimeTests
{
	@Test(arguments: [false, true])
	func samePathOwnerCycleRejectsFirstRequest(lateAfterCurrent: Bool) async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
		)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				runtime.job
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				runtime.shutdown()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			defer
			{
				runtime.shutdown()
			}
			var publications: [[String]?] = []
			runtime.onChange =
			{
				publications.append(runtime.index?.files)
			}
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
			let firstRead = try #require(runtime.job)
			runtime.select(second)
			_ = try await service.path(at: 1)
			let secondRead = try #require(runtime.job)
			runtime.select(first)
			_ = try await service.path(at: 2)
			let currentRead = try #require(runtime.job)
			#expect(runtime.index == nil)
			try await service.waitForCancellation(at: 0)
			try await service.waitForCancellation(at: 1)
			if lateAfterCurrent
			{
				await service.finish(
					at: 2,
					files: ["current.swift"]
				)
				await currentRead.value
				#expect(runtime.index?.files == ["current.swift"])
			}
			let publicationsBeforeObsoleteResults = publications.count
			await service.finish(
				at: 0,
				files: ["stale.swift"]
			)
			await firstRead.value
			await service.finish(
				at: 1,
				files: ["other.swift"]
			)
			await secondRead.value
			#expect(publications.count == publicationsBeforeObsoleteResults)
			#expect(runtime.index?.files == (lateAfterCurrent ? ["current.swift"] : nil))
			if !lateAfterCurrent
			{
				await service.finish(
					at: 2,
					files: ["current.swift"]
				)
				await currentRead.value
			}
			#expect(runtime.index?.files == ["current.swift"])
			#expect(publications.compactMap
			{
				$0
			} == [["current.swift"]])
		}
	}

	@Test func clearAndShutdownCancelPendingEnumeration() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				runtime.job
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				runtime.shutdown()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			defer
			{
				runtime.shutdown()
			}
			var publications = 0
			runtime.onChange =
			{
				publications += 1
			}
			runtime.select(makeOwner(
				path: "/fixture",
				thread: "first"
			))
			_ = try await service.path(at: 0)
			let clearedRead = try #require(runtime.job)
			runtime.select(makeOwner(
				path: nil,
				thread: "first"
			))
			try await service.waitForCancellation(at: 0)
			let publicationsBeforeClearedResult = publications
			await service.finish(
				at: 0,
				files: ["stale.swift"]
			)
			await clearedRead.value
			#expect(runtime.index == nil)
			#expect(publications == publicationsBeforeClearedResult)
			#expect(monitor.observations[0].isCancelled)

			runtime.select(makeOwner(
				path: "/fixture",
				thread: "second"
			))
			_ = try await service.path(at: 1)
			let shutDownRead = try #require(runtime.job)
			runtime.shutdown()
			#expect(monitor.observations[1].isCancelled)
			try await service.waitForCancellation(at: 1)
			await service.finish(
				at: 1,
				files: ["late.swift"]
			)
			await shutDownRead.value
			runtime.select(makeOwner(
				path: "/fixture",
				thread: "third"
			))
			#expect(runtime.index == nil)
			#expect(await service.count == 2)
		}
	}

	@Test func observerSelectionReplacesPendingRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
		)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				runtime.job
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				runtime.shutdown()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
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
			try await waitForIndexChange(in: runtime)
			{
				runtime.index?.files == ["next.swift"]
			}
			#expect(await service.count == 1)
		}
	}

	@Test func observerShutdownPreventsPendingRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
		)
		try await withRuntimeReadCleanup(
			currentTask:
			{
				runtime.job
			},
			observeStarts:
			{
				await service.observeReadStarts($0)
			},
			stop:
			{
				runtime.shutdown()
			},
			releasePending:
			{
				await service.releasePendingReads()
			}
		)
		{
			var cancelledRequest: Task<Void, Never>?
			runtime.onChange =
			{
				[weak runtime] in
				cancelledRequest = runtime?.job
				runtime?.shutdown()
			}
			runtime.select(makeOwner(
				path: "/first",
				thread: "first"
			))
			// Await the asynchronous cancellation guard before checking for service calls.
			await (try #require(cancelledRequest)).value
			#expect(runtime.index == nil)
			#expect(await service.count == 0)
		}
	}

	@Test func synchronousWatchCallbackCannotReplaceNewOwnersObservation() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor(emitDuringFirstWatch: true)
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
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
		#expect(monitor.observations.count == 2)
		#expect(monitor.observations[0].isCancelled)
		#expect(!monitor.observations[1].isCancelled)
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
		runtime.shutdown()
		#expect(monitor.observations[1].isCancelled)
		#expect(await service.count == 1)
	}

	@Test func completedIndexIsReusedAcrossThreadsInWatchedCheckout() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["current.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["current.swift"]
		}

		for thread in ["second", "first", "third"]
		{
			runtime.select(makeOwner(
				path: "/fixture",
				thread: thread
			))
			#expect(runtime.index?.files == ["current.swift"])
		}
		#expect(await service.count == 1)
		#expect(monitor.observations.count == 1)
		#expect(!monitor.observations[0].isCancelled)
		runtime.shutdown()
	}

	@Test func fileChangeBurstInvalidatesCompletedIndexOnce() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["old.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["old.swift"]
		}

		for _ in 0 ..< 20
		{
			monitor.emit(at: 0)
		}
		#expect(runtime.index == nil)
		_ = try await service.path(at: 1)
		#expect(await service.count == 2)
		await service.finish(
			at: 1,
			files: ["new.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["new.swift"]
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		#expect(runtime.index?.files == ["new.swift"])
		#expect(await service.count == 2)
		runtime.shutdown()
	}

	@Test func changesObservedDuringEnumerationRejectOldResult() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor,
			waitForFileChanges:
			{
			}
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		#expect(monitor.observations.count == 1)
		monitor.emit(at: 0)
		_ = try await service.path(at: 1)
		try await waitUntil
		{
			await service.wasCancelled(at: 0)
		}
		await service.finish(
			at: 0,
			files: ["stale.swift"]
		)
		#expect(runtime.index == nil)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
		runtime.shutdown()
	}

	@Test func projectOwnershipChangeDiscardsCacheAndLateWatchEvents() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor,
			waitForFileChanges:
			{
			}
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["first.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["first.swift"]
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first",
			storeIdentity: "replacement"
		))
		#expect(runtime.index == nil)
		#expect(monitor.observations[0].isCancelled)
		_ = try await service.path(at: 1)
		monitor.emit(
			at: 0,
			includingCancelled: true
		)
		await service.finish(
			at: 1,
			files: ["replacement.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["replacement.swift"]
		}
		#expect(await service.count == 2)
		runtime.shutdown()
		monitor.emit(
			at: 1,
			includingCancelled: true
		)
		#expect(runtime.index == nil)
		#expect(await service.count == 2)
	}

	@Test func unavailableWatcherRevalidatesAfterThreadSwitch() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor(isAvailable: false)
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["old.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["old.swift"]
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		#expect(runtime.index == nil)
		_ = try await service.path(at: 1)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
		runtime.shutdown()
	}

	@Test func changedRootRebindsObservationAndIgnoresRetiredCallbacks() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor,
			waitForFileChanges:
			{
			}
		)
		defer
		{
			runtime.shutdown()
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["before.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["before.swift"]
		}

		monitor.observations[0].invalidate()
		monitor.emit(at: 0)
		#expect(monitor.observations.count == 2)
		#expect(monitor.observations[0].isCancelled)
		#expect(runtime.index == nil)
		_ = try await service.path(at: 1)
		monitor.emit(
			at: 0,
			includingCancelled: true
		)
		await service.finish(
			at: 1,
			files: ["after.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["after.swift"]
		}
		#expect(await service.count == 2)
		#expect(!monitor.observations[1].isCancelled)
	}

	@Test func unavailableWatcherIsRetriedForTheNextOwner() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor(isAvailable: false)
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		defer
		{
			runtime.shutdown()
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["old.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["old.swift"]
		}

		monitor.isAvailable = true
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		#expect(monitor.observations.count == 1)
		_ = try await service.path(at: 1)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "third"
		))
		#expect(runtime.index?.files == ["fresh.swift"])
		#expect(await service.count == 2)
	}

	@Test func changedRootDuringEnumerationRejectsTheOldPhysicalRoot() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor,
			waitForFileChanges:
			{
			}
		)
		defer
		{
			runtime.shutdown()
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		monitor.observations[0].invalidate()
		await service.finish(
			at: 0,
			files: ["stale.swift"]
		)
		_ = try await service.path(at: 1)
		#expect(runtime.index == nil)
		#expect(monitor.observations.count == 2)
		#expect(monitor.observations[0].isCancelled)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
		#expect(await service.count == 2)
	}

	@Test func synchronousRebindingCallbackStartsOnlyItsLatestRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor(emitDuringWatchAt: 1)
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor,
			waitForFileChanges:
			{
			}
		)
		defer
		{
			runtime.shutdown()
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["old.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["old.swift"]
		}
		monitor.observations[0].invalidate()
		monitor.emit(at: 0)
		_ = try await service.path(at: 1)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
		#expect(await service.count == 2)
		#expect(monitor.observations.count == 2)
	}

	@Test func changedRootIsRevalidatedBeforeReusingAThreadSwitchCache() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		defer
		{
			runtime.shutdown()
		}
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "first"
		))
		_ = try await service.path(at: 0)
		await service.finish(
			at: 0,
			files: ["old.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["old.swift"]
		}
		monitor.observations[0].invalidate()
		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		#expect(runtime.index == nil)
		#expect(monitor.observations.count == 2)
		#expect(monitor.observations[0].isCancelled)
		_ = try await service.path(at: 1)
		await service.finish(
			at: 1,
			files: ["fresh.swift"]
		)
		try await waitUntil
		{
			runtime.index?.files == ["fresh.swift"]
		}
	}

	@Test func unwatchedReferencesAreRescannedAcrossThreadOwners() async throws
	{
		let service = ControlledProjectFileIndexService()
		let monitor = ManualProjectFileIndexMonitor()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: monitor
		)
		defer
		{
			runtime.shutdown()
		}
		for (request, thread) in ["first", "second", "first"].enumerated()
		{
			runtime.select(makeOwner(
				path: "/fixture",
				thread: thread
			))
			#expect(runtime.index == nil)
			_ = try await service.path(at: request)
			let files = request == 1 ? [] : ["linked.swift"]
			await service.finish(
				at: request,
				files: files,
				isReusableWithProjectObservation: false
			)
			try await waitUntil
			{
				runtime.index?.files == files
			}
		}
		#expect(await service.count == 3)
		#expect(monitor.observations.count == 1)
		#expect(!monitor.observations[0].isCancelled)
	}

	private func makeOwner(
		path: String?,
		thread: String,
		storeIdentity: String = "test"
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
			storeIdentity: storeIdentity
		)
	}

	// Publication is an explicit runtime event, independent of other tests' actor workload.
	private func waitForIndexChange(
		in runtime: ProjectFileIndexRuntime,
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
			previousChange?()
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
	private func waitUntil(
		attempts: Int = 100,
		_ condition: () async -> Bool
	) async throws
	{
		for _ in 0 ..< attempts
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

@MainActor
private final class ManualProjectFileIndexMonitor: ProjectFileIndexMonitoring
{
	var isAvailable: Bool
	private let emitDuringFirstWatch: Bool
	private let emitDuringWatchAt: Int?
	private var callbacks: [@MainActor () -> Void] = []
	private(set) var observations: [ManualProjectFileIndexObservation] = []

	init(
		isAvailable: Bool = true,
		emitDuringFirstWatch: Bool = false,
		emitDuringWatchAt: Int? = nil
	)
	{
		self.isAvailable = isAvailable
		self.emitDuringFirstWatch = emitDuringFirstWatch
		self.emitDuringWatchAt = emitDuringWatchAt
	}

	func watch(
		projectPath: String,
		onChange: @escaping @MainActor () -> Void
	) -> (any ProjectFileIndexObservation)?
	{
		guard isAvailable
		else
		{
			return nil
		}
		let observation = ManualProjectFileIndexObservation()
		observations.append(observation)
		callbacks.append(onChange)
		let shouldEmitDuringWatch = emitDuringFirstWatch && observations.count == 1
			|| emitDuringWatchAt == observations.count - 1
		if shouldEmitDuringWatch
		{
			onChange()
		}
		return observation
	}

	func emit(
		at index: Int,
		includingCancelled: Bool = false
	)
	{
		if includingCancelled || !observations[index].isCancelled
		{
			callbacks[index]()
		}
	}
}

private final class ManualProjectFileIndexObservation: ProjectFileIndexObservation,
	@unchecked Sendable
{
	private let lock = NSLock()
	private var cancelled = false
	private var current = true

	var isCurrent: Bool
	{
		lock.withLock
		{
			current && !cancelled
		}
	}

	var isCancelled: Bool
	{
		lock.withLock
		{
			cancelled
		}
	}

	func cancel()
	{
		lock.withLock
		{
			cancelled = true
		}
	}

	func invalidate()
	{
		lock.withLock
		{
			current = false
		}
	}
}

private actor ControlledProjectFileIndexService: ProjectFileIndexService
{
	private var paths: [String] = []
	private var readyPaths: Set<Int> = []
	private var onReadStarted: (@MainActor @Sendable () -> Void)?
	private var isTearingDown = false
	private var continuations: [Int: CheckedContinuation<ProjectFileIndex?, Never>] = [:]
	private var cancelled: Set<Int> = []
	private var pathWaiters: [Int: [UUID: AsyncStream<String>.Continuation]] = [:]
	private var cancellationWaiters: [Int: [UUID: AsyncStream<Void>.Continuation]] = [:]

	var count: Int
	{
		paths.count
	}

	func load(projectPath: String) async -> ProjectFileIndex?
	{
		guard !isTearingDown
		else
		{
			return nil
		}
		let index = paths.count
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				paths.append(projectPath)
				continuations[index] = continuation
				Task
				{
					await onReadStarted?()
					readyPaths.insert(index)
					for waiter in (pathWaiters.removeValue(forKey: index) ?? [:]).values
					{
						waiter.yield(projectPath)
						waiter.finish()
					}
				}
			}
		} onCancel:
		{
			Task
			{
				await self.markCancelled(index)
			}
		}
	}

	// Await mock entry and cancellation directly rather than budgeting actor scheduling time.
	func path(at index: Int) async throws -> String
	{
		try Task.checkCancellation()
		if readyPaths.contains(index)
		{
			return paths[index]
		}
		let id = UUID()
		let checkpoint = AsyncStream<String>.makeStream()
		pathWaiters[index, default: [:]][id] = checkpoint.continuation
		defer
		{
			pathWaiters[index]?.removeValue(forKey: id)
			if pathWaiters[index]?.isEmpty == true
			{
				pathWaiters.removeValue(forKey: index)
			}
			checkpoint.continuation.finish()
		}
		for await path in checkpoint.stream
		{
			try Task.checkCancellation()
			return path
		}
		throw CancellationError()
	}

	func waitForCancellation(at index: Int) async throws
	{
		try Task.checkCancellation()
		guard !cancelled.contains(index)
		else
		{
			return
		}
		let id = UUID()
		let checkpoint = AsyncStream<Void>.makeStream()
		cancellationWaiters[index, default: [:]][id] = checkpoint.continuation
		defer
		{
			cancellationWaiters[index]?.removeValue(forKey: id)
			if cancellationWaiters[index]?.isEmpty == true
			{
				cancellationWaiters.removeValue(forKey: index)
			}
			checkpoint.continuation.finish()
		}
		for await _ in checkpoint.stream
		{
			break
		}
		try Task.checkCancellation()
	}

	func finish(
		at index: Int,
		files: [String],
		isReusableWithProjectObservation: Bool = true
	)
	{
		continuations.removeValue(forKey: index)!.resume(returning: ProjectFileIndex(
			files: files,
			isReusableWithProjectObservation: isReusableWithProjectObservation
		))
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
			continuation.resume(returning: nil)
		}
	}

	private func markCancelled(_ index: Int)
	{
		cancelled.insert(index)
		for waiter in (cancellationWaiters.removeValue(forKey: index) ?? [:]).values
		{
			waiter.yield(())
			waiter.finish()
		}
	}

	func wasCancelled(at index: Int) -> Bool
	{
		cancelled.contains(index)
	}

}
