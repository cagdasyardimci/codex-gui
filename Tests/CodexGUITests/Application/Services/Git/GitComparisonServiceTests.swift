import Foundation
import Testing

@testable import CodexGUI

struct GitComparisonServiceTests
{
	@Test func parsesFullContextWithoutTreatingSourceAsMetadata() throws
	{
		let patch = """
		diff --git a/old.swift b/new.swift
		similarity index 75%
		rename from old.swift
		rename to new.swift
		--- a/old.swift
		+++ b/new.swift
		@@ -1,3 +1,3 @@
		 context
		-old
		+new
		 +++ source context
		"""
		let file = try #require(GitComparisonPatchParser.files(in: Data(patch.utf8)).first)
		#expect(file.oldPath == "old.swift")
		#expect(file.newPath == "new.swift")
		#expect(file.kind == .renamed)
		#expect(file.additions == 1)
		#expect(file.deletions == 1)
		#expect(file.hunks.first?.text.contains(" +++ source context") == true)
	}

	@Test func binaryAndQuotedPathMetadataRemainDistinct() throws
	{
		let patch = "diff --git \"a/tab\\tfile\" \"b/tab\\tfile\"\n"
			+ "Binary files \"a/tab\\tfile\" and \"b/tab\\tfile\" differ\n"
		let file = try #require(GitComparisonPatchParser.files(in: Data(patch.utf8)).first)
		#expect(file.isBinary)
		#expect(file.path == "tab\tfile")
		#expect(file.hunks.isEmpty)
	}

	@Test func combinedConflictSectionCannotJoinEarlierFile() throws
	{
		let patch = "diff --git a/first b/first\n--- a/first\n+++ b/first\n"
			+ "@@ -1 +1 @@\n-old\n+new\n"
			+ "diff --cc conflict\nindex 1111111,2222222..3333333\n"
			+ "@@@ -1,1 -1,1 +1,1 @@@\n++resolved\n"
		let bytes = Data(patch.utf8)
		#expect(GitComparisonPatchParser.hasUnsupportedSections(in: bytes))
		let files = GitComparisonPatchParser.files(in: bytes)
		#expect(files.count == 1)
		#expect(files.first?.path == "first")
		#expect(files.first?.patch.contains("diff --cc") == false)
	}

	@Test func cancellingComparisonStopsDetachedProcess() async throws
	{
		let started = DispatchSemaphore(value: 0)
		let work = Task
		{
			await GitSubprocessCancellation.detached
			{
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/bin/sleep")
				process.arguments = ["5"]
				guard let control = GitSubprocessCancellation.current
				else
				{
					return false
				}
				do
				{
					try control.launch(process)
					started.signal()
					process.waitUntilExit()
					control.finish(process)
					return Task.isCancelled && process.terminationStatus != 0
				}
				catch
				{
					return false
				}
			}
		}
		let didStart = await Task.detached
		{
			Self.waitForSignal(started)
		}.value
		#expect(didStart)
		let cancelledAt = Date()
		work.cancel()
		#expect(await work.value)
		#expect(Date().timeIntervalSince(cancelledAt) < 2)
	}

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

	@Test func comparisonsPreserveIndexWorkingTreeAndUntrackedPolicy() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		try git(
			root,
			["init", "-q"]
		)
		let file = root.appendingPathComponent("neutral file.txt")
		try Data("original\ncontext\n".utf8).write(to: file)
		try git(
			root,
			["add", "--", "neutral file.txt"]
		)
		try git(
			root,
			["-c",
				"user.name=Test",
				"-c",
				"user.email=test@example.invalid",
				"commit",
				"-qm",
				"Fixture"]
		)
		try Data("staged\ncontext\n".utf8).write(to: file)
		try git(
			root,
			["add", "--", "neutral file.txt"]
		)
		try Data("working\ncontext\n".utf8).write(to: file)
		let untracked = root.appendingPathComponent("untracked.txt")
		try Data("untracked\n".utf8).write(to: untracked)
		let index = root.appendingPathComponent(".git/index")
		let indexBefore = try Data(contentsOf: index)
		let statusBefore = try git(
			root,
			["status", "--porcelain=v2", "-z"]
		)
		let service = LocalGitComparisonService()
		for scope in [GitComparisonScope.unstaged, .staged, .uncommitted]
		{
			let result = await service.compare(request(
				root: root.path,
				scope: scope
			))
			guard case .snapshot(let snapshot) = result
			else
			{
				Issue.record("Expected a comparison: \(result)")
				continue
			}
			#expect(snapshot.files.map(\.path) == ["neutral file.txt"])
			#expect(snapshot.additions == 1)
			#expect(snapshot.deletions == 1)
			let text = String(
				decoding: snapshot.patch,
				as: UTF8.self
			)
			#expect(text.contains(" context"))
			#expect(text.contains(scope == .staged ? "+staged" : "+working"))
			#expect(text.contains(scope == .unstaged ? "-staged" : "-original"))
		}
		#expect(try Data(contentsOf: index) == indexBefore)
		#expect(try Data(contentsOf: file) == Data("working\ncontext\n".utf8))
		#expect(try git(
			root,
			["status", "--porcelain=v2", "-z"]
		) == statusBefore)
	}

	@Test func unmergedIndexIsUnavailableForStagedAndUnstaged() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		try git(
			root,
			["init", "-q"]
		)
		let path = root.appendingPathComponent("conflict.txt")
		try Data("base\n".utf8).write(to: path)
		try git(
			root,
			["add", "--", "conflict.txt"]
		)
		try git(
			root,
			["-c",
				"user.name=Test",
				"-c",
				"user.email=test@example.invalid",
				"commit",
				"-qm",
				"Fixture"]
		)
		let blob = String(
			decoding: try git(
				root,
				["rev-parse", "HEAD:conflict.txt"]
			),
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let stages = "0 " + String(
			repeating: "0",
			count: 40
		) + "\tconflict.txt\n"
			+ "100644 " + blob + " 1\tconflict.txt\n"
			+ "100644 " + blob + " 2\tconflict.txt\n"
			+ "100644 " + blob + " 3\tconflict.txt\n"
		try gitWithInput(
			root,
			["update-index", "--index-info"],
			Data(stages.utf8)
		)
		let service = LocalGitComparisonService()
		for scope in [GitComparisonScope.staged, .unstaged]
		{
			#expect(await service.compare(request(
				root: root.path,
				scope: scope
			)) == .unavailable(.unmergedIndex))
		}
	}

	@Test func unavailableScopesAndNonGitRepositoryAreExplicit() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		let service = LocalGitComparisonService()
		#expect(await service.compare(request(
			root: root.path,
			scope: .unstaged
		))
			== .unavailable(.notGitRepository))
		#expect(await service.compare(request(
			root: root.path,
			scope: .lastTurn
		))
			== .unavailable(.lastTurnUnavailable))
		try git(
			root,
			["init", "-q"]
		)
		guard case .snapshot(let empty) = await service.compare(
			request(
				root: root.path,
				scope: .unstaged
			)
		)
		else
		{
			Issue.record("Unborn repository supports unstaged comparisons")
			return
		}
		#expect(empty.files.isEmpty)
		#expect(await service.compare(request(
			root: root.path,
			scope: .staged
		))
			== .unavailable(.invalidRevision("HEAD")))
	}

	@Test func explicitRevisionDirectionAndInvalidTextAreSupported() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		try git(
			root,
			["init", "-q"]
		)
		let file = root.appendingPathComponent("source.txt")
		for text in ["first\n", "second\n"]
		{
			try Data(text.utf8).write(to: file)
			try git(
				root,
				["add", "--", "source.txt"]
			)
			try git(
				root,
				["-c",
					"user.name=Test",
					"-c",
					"user.email=test@example.invalid",
					"commit",
					"-qm",
					"Fixture"]
			)
		}
		let service = LocalGitComparisonService()
		var comparison = request(
			root: root.path,
			scope: .branch
		)
		comparison.baseRevision = "HEAD"
		comparison.targetRevision = "HEAD^"
		guard case .snapshot(let reversed) = await service.compare(comparison)
		else
		{
			Issue.record("Expected explicit reversed comparison")
			return
		}
		let patch = String(
			decoding: reversed.patch,
			as: UTF8.self
		)
		#expect(patch.contains("-second"))
		#expect(patch.contains("+first"))
		#expect(reversed.resolvedBase != reversed.resolvedTarget)
		comparison.baseRevision = "--help"
		#expect(await service.compare(comparison) == .unavailable(.invalidRevision("--help")))
		try Data([0xFF, 0x0A]).write(to: file)
		#expect(await service.compare(request(
			root: root.path,
			scope: .unstaged
		))
			== .unavailable(.unsupportedTextEncoding))
	}

	@Test func markerSeparatorsDoNotDamageTabsInNames() throws
	{
		let quoted = "diff --git \"a/end\\t\" \"b/end\\t\"\n"
			+ "--- \"a/end\\t\"\n+++ \"b/end\\t\"\n@@ -1 +1 @@\n-a\n+b\n"
		let file = try #require(GitComparisonPatchParser.files(in: Data(quoted.utf8)).first)
		#expect(file.path == "end\t")
		let binary = "diff --git a/folder b/name b/folder b/name\n"
			+ "Binary files a/folder b/name and b/folder b/name differ\n"
		let binaryFile = try #require(GitComparisonPatchParser.files(in: Data(binary.utf8)).first)
		#expect(binaryFile.path == "folder b/name")
	}

	@Test func repositoryProgramsCannotRunDuringComparison() async throws
	{
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: root,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: root)
		}
		try git(
			root,
			["init", "-q"]
		)
		let file = root.appendingPathComponent("source.txt")
		try Data("before\n".utf8).write(to: file)
		try Data("*.txt filter=unsafe\n".utf8).write(
			to: root.appendingPathComponent(".gitattributes")
		)
		try git(
			root,
			["add", "--", "source.txt", ".gitattributes"]
		)
		try git(
			root,
			["-c",
				"user.name=Test",
				"-c",
				"user.email=test@example.invalid",
				"commit",
				"-qm",
				"Fixture"]
		)
		try git(
			root,
			["config", "filter.unsafe.clean", "touch filter-ran; cat"]
		)
		try git(
			root,
			["config", "filter.unsafe.required", "true"]
		)
		try Data("after\n".utf8).write(to: file)
		let result = await LocalGitComparisonService().compare(
			request(
				root: root.path,
				scope: .unstaged
			)
		)
		guard case .snapshot(let snapshot) = result
		else
		{
			Issue.record("Expected comparison with configured filters disabled")
			return
		}
		#expect(snapshot.additions == 1)
		#expect(!FileManager.default
			.fileExists(atPath: root.appendingPathComponent("filter-ran").path))
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

	@discardableResult
	private func git(
		_ root: URL,
		_ arguments: [String]
	) throws -> Data
	{
		let result = try GitTestCommandRunner.run(
			in: root,
			arguments: arguments
		)
		#expect(result.terminationStatus == 0)
		return result.output
	}

	private func gitWithInput(
		_ root: URL,
		_ arguments: [String],
		_ bytes: Data
	) throws
	{
		let result = try GitTestCommandRunner.run(
			in: root,
			arguments: arguments,
			input: bytes
		)
		#expect(result.terminationStatus == 0)
	}

	private static func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool
	{
		semaphore.wait(timeout: .now() + 2) == .success
	}
}
