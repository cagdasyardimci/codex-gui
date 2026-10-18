import Foundation
import Testing

@testable import CodexGUI

struct GitComparisonSnapshotTests
{
	@Test func copyPayloadPreservesExactBytesAndRejectsBinary() throws
	{
		let patch = Data("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n".utf8)
		let snapshot = GitComparisonSnapshot(
			request: request(
				root: "/tmp/fixture",
				scope: .unstaged
			),
			id: "fixture",
			resolvedBase: "Index",
			resolvedTarget: "Working tree",
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch)
		)
		let command = try #require(snapshot.copyCommand)
		#expect(command == "printf '%s' '" + patch.base64EncodedString()
			+ "' | base64 -D | git -C '/tmp/fixture' apply")
		let binary = Data("diff --git a/x b/x\nBinary files a/x and b/x differ\n".utf8)
		let unsupported = GitComparisonSnapshot(
			request: snapshot.request,
			id: "binary",
			resolvedBase: "Index",
			resolvedTarget: "Working tree",
			patch: binary,
			files: GitComparisonPatchParser.files(in: binary)
		)
		#expect(unsupported.copyCommand == nil)
	}

	@Test func copiedReportedPatchAppliesInARepositoryWithAnApostrophe() async throws
	{
		let container = FileManager.default.temporaryDirectory
			.appendingPathComponent("GitCopyCommand-\(UUID().uuidString)")
		let root = container.appendingPathComponent("owner's checkout")
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: container)
		}
		let initialized = try GitTestCommandRunner.run(
			in: root,
			arguments: ["init", "-q"]
		)
		try #require(initialized.terminationStatus == 0)
		let source = root.appendingPathComponent("source.txt")
		let unrelated = container.appendingPathComponent("source.txt")
		try Data("first\nold\nlast\n".utf8).write(to: source)
		try Data("unrelated\n".utf8).write(to: unrelated)
		var comparison = request(
			root: root.path,
			scope: .lastTurn
		)
		comparison.lastTurnID = "editing-turn"
		comparison.reportedChanges = [try #require(FileChange(json: [
			"path": "source.txt",
			"kind": "update",
			"diff": "@@ -2 +2 @@\n-old\n+new\n",
		]))]
		guard case .snapshot(let snapshot) = await LocalGitComparisonService().compare(comparison)
		else
		{
			Issue.record("Expected the recorded zero-context edit to produce a copy command")
			return
		}
		let command = try #require(snapshot.copyCommand)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", command]
		process.currentDirectoryURL = container
		var environment = ProcessInfo.processInfo.environment
		for key in environment.keys where key.hasPrefix("GIT_")
		{
			environment.removeValue(forKey: key)
		}
		environment["PATH"] = "/usr/bin:/bin"
		environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
		environment["GIT_CONFIG_NOSYSTEM"] = "1"
		process.environment = environment
		let output = Pipe()
		defer
		{
			try? output.fileHandleForReading.close()
			try? output.fileHandleForWriting.close()
		}
		process.standardOutput = output
		process.standardError = output
		process.standardInput = FileHandle.nullDevice
		try process.run()
		let diagnostics = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		#expect(
			process.terminationStatus == 0,
			"\(String(decoding: diagnostics, as: UTF8.self))"
		)
		#expect(try Data(contentsOf: source) == Data("first\nnew\nlast\n".utf8))
		#expect(try Data(contentsOf: unrelated) == Data("unrelated\n".utf8))
	}

	@Test(arguments: ["createRename", "createRenameDelete", "renameDelete"])
	func generatedReportedPatchesRespectNetFileExistence(_ sequence: String) async throws
	{
		let root = try await BackgroundTestWork.perform
		{
			let root = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(
				at: root,
				withIntermediateDirectories: true
			)
			if sequence == "renameDelete"
			{
				try Data("content\n".utf8).write(to: root.appendingPathComponent("A.swift"))
			}
			return root
		}
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let initialized = try await GitTestCommandRunner.runAsync(
			in: root,
			arguments: ["init", "-q"]
		)
		try #require(initialized.terminationStatus == 0)
		let created = fileChange(
			"content\n",
			kind: "add",
			path: "A.swift"
		)
		let renamed = fileChange(
			"",
			path: "A.swift",
			movePath: "B.swift"
		)
		let deleted = fileChange(
			"content\n",
			kind: "delete",
			path: "B.swift"
		)
		let changes = sequence == "createRename" ? [created, renamed]
			: sequence == "createRenameDelete" ? [created, renamed, deleted] : [renamed, deleted]
		var comparison = request(
			root: root.path,
			scope: .lastTurn
		)
		comparison.lastTurnID = "editing"
		comparison.reportedChanges = changes
		guard case .snapshot(let snapshot) = GitReportedTurnComparison.compare(comparison)
		else
		{
			Issue.record("Expected an exact reported comparison")
			return
		}
		#expect(!snapshot.usesReportedEditFallback)
		if sequence == "createRenameDelete"
		{
			#expect(snapshot.files.isEmpty)
			#expect(snapshot.patch.isEmpty)
			#expect(snapshot.copyCommand == nil)
			return
		}
		#expect(snapshot.files.map(\.path) == [sequence == "createRename" ? "B.swift" : "A.swift"])
		#expect(snapshot.files.first?.kind == (sequence == "createRename" ? .added : .deleted))
		#expect(snapshot.copyCommand != nil)
		let checked = try await GitTestCommandRunner.runAsync(
			in: root,
			arguments: ["apply", "--check", "--unidiff-zero"],
			input: snapshot.patch,
			captureStandardError: true
		)
		#expect(
			checked.terminationStatus == 0,
			"\(String(decoding: checked.output, as: UTF8.self))"
		)
		let applied = try await GitTestCommandRunner.runAsync(
			in: root,
			arguments: ["apply", "--unidiff-zero"],
			input: snapshot.patch,
			captureStandardError: true
		)
		#expect(
			applied.terminationStatus == 0,
			"\(String(decoding: applied.output, as: UTF8.self))"
		)
		#expect(!FileManager.default
			.fileExists(atPath: root.appendingPathComponent("A.swift").path))
		if sequence == "createRename"
		{
			#expect(try Data(contentsOf: root.appendingPathComponent("B.swift")) ==
				Data("content\n".utf8))
		}
		else
		{
			#expect(!FileManager.default
				.fileExists(atPath: root.appendingPathComponent("B.swift").path))
		}
	}

	@Test func equivalentReportedPathsComposeIntoOneApplicablePatch() async throws
	{
		let root = try await BackgroundTestWork.perform
		{
			let root = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(
				at: root,
				withIntermediateDirectories: true
			)
			try Data("original\n".utf8).write(to: root.appendingPathComponent("A.swift"))
			return root
		}
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let initialized = try await GitTestCommandRunner.runAsync(
			in: root,
			arguments: ["init", "-q"]
		)
		try #require(initialized.terminationStatus == 0)
		let paths = ["A.swift", "./A.swift", "folder/../A.swift", root.path + "/A.swift"]
		let values = ["original", "one", "two", "three", "final"]
		let changes = paths.enumerated().map
		{
			index, path in
			fileChange(
				"@@ -1 +1 @@\n-\(values[index])\n+\(values[index + 1])",
				path: path
			)
		}
		var comparison = request(
			root: root.path + "/./",
			scope: .lastTurn
		)
		comparison.lastTurnID = "editing"
		comparison.reportedChanges = changes
		guard case .snapshot(let snapshot) = GitReportedTurnComparison.compare(comparison)
		else
		{
			Issue.record("Expected a normalized reported comparison")
			return
		}
		#expect(!snapshot.usesReportedEditFallback)
		#expect(snapshot.files.map(\.path) == ["A.swift"])
		#expect(snapshot.additions == 1)
		#expect(snapshot.deletions == 1)
		#expect(snapshot.request.reportedChanges?.map(\.path) == paths)
		let checked = try await GitTestCommandRunner.runAsync(
			in: root,
			arguments: ["apply", "--check", "--unidiff-zero"],
			input: snapshot.patch,
			captureStandardError: true
		)
		#expect(
			checked.terminationStatus == 0,
			"\(String(decoding: checked.output, as: UTF8.self))"
		)
	}

	private func fileChange(
		_ diff: String,
		kind: String = "update",
		path: String,
		movePath: String? = nil
	) -> FileChange
	{
		var metadata = ["type": kind]
		metadata["move_path"] = movePath
		return FileChange(json: ["path": path, "kind": metadata, "diff": diff])!
	}

	private func request(
		root: String,
		scope: GitComparisonScope
	) -> GitComparisonRequest
	{
		let snapshot = ConversationSnapshot(
			projectPath: root,
			threads: [],
			selectedThreadID: "fixture-thread",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "",
			backendDescription: "",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		return GitComparisonRequest(
			owner: FeaturePresentationOwner(snapshot),
			repositoryRoot: root,
			scope: scope,
			generation: 1
		)
	}
}
