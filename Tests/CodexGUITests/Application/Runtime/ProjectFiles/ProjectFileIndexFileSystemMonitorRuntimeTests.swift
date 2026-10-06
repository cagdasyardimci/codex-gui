import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ProjectFileIndexFileSystemMonitorRuntimeTests
{
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
