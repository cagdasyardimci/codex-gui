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
