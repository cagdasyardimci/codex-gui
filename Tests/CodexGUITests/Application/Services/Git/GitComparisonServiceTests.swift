import Foundation
import Testing

@testable import CodexGUI

struct GitComparisonServiceTests
{
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

}
