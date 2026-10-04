import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ProjectFileIndexRuntimeTests
{
	@Test func samePathOwnerCycleRejectsFirstRequest() async throws
	{
		let service = ControlledProjectFileIndexService()
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
		)
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
		#expect(monitor.observations[0].isCancelled)

		runtime.select(makeOwner(
			path: "/fixture",
			thread: "second"
		))
		_ = try await service.path(at: 1)
		runtime.shutdown()
		#expect(monitor.observations[1].isCancelled)
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
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
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
		let runtime = ProjectFileIndexRuntime(
			service: service,
			monitor: ManualProjectFileIndexMonitor()
		)
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

	@Test func fileSystemMonitorRecoversAfterRootDeletionAndRecreation() async throws
	{
		let directory = try makeTemporaryDirectory()
		let project = directory.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		try writeFile(
			named: "old.swift",
			in: project
		)
		let runtime = ProjectFileIndexRuntime()
		defer
		{
			runtime.shutdown()
			try? FileManager.default.removeItem(at: directory)
		}
		runtime.select(makeOwner(
			path: project.path,
			thread: "first"
		))
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["old.swift"]
		}
		try FileManager.default.removeItem(at: project)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == []
		}

		try FileManager.default.createDirectory(
			at: project,
			withIntermediateDirectories: true
		)
		try writeFile(
			named: "new.swift",
			in: project
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["new.swift"]
		}
		try writeFile(
			named: "later.swift",
			in: project
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["later.swift", "new.swift"]
		}
	}

	@Test func fileSystemMonitorRebindsAfterCheckoutAliasRetargeting() async throws
	{
		let directory = try makeTemporaryDirectory()
		let first = directory.appendingPathComponent(
			"first",
			isDirectory: true
		)
		let second = directory.appendingPathComponent(
			"second",
			isDirectory: true
		)
		let alias = directory.appendingPathComponent(
			"checkout",
			isDirectory: true
		)
		for project in [first, second]
		{
			try FileManager.default.createDirectory(
				at: project,
				withIntermediateDirectories: true
			)
		}
		try writeFile(
			named: "first.swift",
			in: first
		)
		try writeFile(
			named: "second.swift",
			in: second
		)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: first
		)
		let runtime = ProjectFileIndexRuntime()
		defer
		{
			runtime.shutdown()
			try? FileManager.default.removeItem(at: directory)
		}
		runtime.select(makeOwner(
			path: alias.path,
			thread: "first"
		))
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["first.swift"]
		}
		try FileManager.default.removeItem(at: alias)
		try FileManager.default.createSymbolicLink(
			at: alias,
			withDestinationURL: second
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["second.swift"]
		}

		try writeFile(
			named: "later.swift",
			in: second
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["later.swift", "second.swift"]
		}
		try writeFile(
			named: "retired.swift",
			in: first
		)
		try await Task.sleep(for: .milliseconds(500))
		#expect(runtime.index?.files == ["later.swift", "second.swift"])
	}

	@Test func fileSystemMonitorRefreshesNestedCreateRenameAndDelete() async throws
	{
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ProjectFileIndexRuntime-\(UUID().uuidString)",
			isDirectory: true
		)
		let nested = directory.appendingPathComponent(
			"Sources/Nested",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: nested,
			withIntermediateDirectories: true
		)
		let dependencies = directory.appendingPathComponent(
			"node_modules/Library",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: dependencies,
			withIntermediateDirectories: true
		)
		let runtime = ProjectFileIndexRuntime()
		var notifications = 0
		runtime.onChange =
		{
			notifications += 1
		}
		defer
		{
			runtime.shutdown()
			try? FileManager.default.removeItem(at: directory)
		}
		runtime.select(makeOwner(
			path: directory.path,
			thread: "first"
		))
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == []
		}
		let original = nested.appendingPathComponent("original.swift")
		try "content".write(
			to: original,
			atomically: true,
			encoding: .utf8
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["Sources/Nested/original.swift"]
		}
		let renamed = nested.appendingPathComponent("renamed.swift")
		try FileManager.default.moveItem(
			at: original,
			to: renamed
		)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == ["Sources/Nested/renamed.swift"]
		}
		try FileManager.default.removeItem(at: renamed)
		try await waitUntil(attempts: 500)
		{
			runtime.index?.files == []
		}
		try await Task.sleep(for: .milliseconds(300))
		let notificationsBeforeIgnoredChange = notifications
		try "dependency".write(
			to: dependencies.appendingPathComponent("library.js"),
			atomically: true,
			encoding: .utf8
		)
		try await Task.sleep(for: .milliseconds(500))
		#expect(runtime.index?.files == [])
		#expect(notifications == notificationsBeforeIgnoredChange)
	}

	private func makeTemporaryDirectory() throws -> URL
	{
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"ProjectFileIndexRuntime-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		return directory
	}

	private func writeFile(
		named name: String,
		in directory: URL
	) throws
	{
		try "content".write(
			to: directory.appendingPathComponent(name),
			atomically: true,
			encoding: .utf8
		)
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
		files: [String],
		isReusableWithProjectObservation: Bool = true
	)
	{
		continuations[index].resume(returning: ProjectFileIndex(
			files: files,
			isReusableWithProjectObservation: isReusableWithProjectObservation
		))
	}

	private func markCancelled(_ index: Int)
	{
		cancelled.insert(index)
	}

	private struct TimeoutError: Error
	{
	}
}
