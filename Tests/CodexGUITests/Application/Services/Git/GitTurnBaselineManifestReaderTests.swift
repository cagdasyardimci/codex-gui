import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselineManifestReaderTests
{
	@Test func unchangedTreeIsReadOnceUsingItsResolvedObjectID() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var commands: [[String]] = []
		var reader = GitTurnBaselineManifestReader
		{
			arguments in
			commands.append(arguments)
			return try fixture.git(arguments)
		}
		let before = try reader.read()
		let after = try reader.read()
		let objectID = String(
			decoding: try fixture.git(["rev-parse", "--verify", "HEAD^{tree}"]),
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(before == after)
		#expect(before.paths == ["source.txt"])
		#expect(commands.count == 5)
		#expect(commands.filter
		{
			$0.first == "ls-tree"
		} == [
			["ls-tree", "--full-tree", "-rz", objectID]
		])
		#expect(commands.filter
		{
			$0.first == "ls-files"
		}.count == 2)
		#expect(commands.filter
		{
			$0.first == "rev-parse"
		}.count == 2)

		var nextCapture = GitTurnBaselineManifestReader
		{
			arguments in
			commands.append(arguments)
			return try fixture.git(arguments)
		}
		#expect(try nextCapture.read() == before)
		#expect(commands.filter
		{
			$0.first == "ls-tree"
		}.count == 2)
	}

	@Test func indexChangesRemainVisibleWhileTheHEADTreeIsReused() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var treeReads = 0
		var reader = GitTurnBaselineManifestReader
		{
			arguments in
			if arguments.first == "ls-tree"
			{
				treeReads += 1
			}
			return try fixture.git(arguments)
		}
		let before = try reader.read()
		try fixture.write(
			"source.txt",
			"staged replacement\n"
		)
		try fixture.write(
			"added ü.txt",
			"staged addition\n"
		)
		try fixture.git(["add", "--", "source.txt", "added ü.txt"])
		let after = try reader.read()
		#expect(before != after)
		#expect(before.index != after.index)
		#expect(before.headTree == after.headTree)
		#expect(after.paths == ["added ü.txt", "source.txt"])
		#expect(treeReads == 1)
	}

	@Test func changedHEADTreesAreReadAgainAndSameTreeCommitsReuseTheirContent() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var treeReads = 0
		var reader = GitTurnBaselineManifestReader
		{
			arguments in
			if arguments.first == "ls-tree"
			{
				treeReads += 1
			}
			return try fixture.git(arguments)
		}
		let before = try reader.read()
		try fixture.write(
			"added.txt",
			"new committed path\n"
		)
		try fixture.git(["add", "--", "added.txt"])
		try fixture.commit()
		let changed = try reader.read()
		#expect(changed.headTree != before.headTree)
		#expect(changed.paths == ["added.txt", "source.txt"])
		#expect(treeReads == 2)
		try fixture.git([
			"-c",
			"user.name=Test",
			"-c",
			"user.email=test@example.invalid",
			"commit",
			"--allow-empty",
			"-qm",
			"Same tree"
		])
		#expect(try reader.read() == changed)
		#expect(treeReads == 2)
	}

	@Test func unbornHEADAndStagedDeletionsPreserveTheTrackedPathUnion() throws
	{
		let fixture = try GitTurnBaselineFixture(commitInitial: false)
		defer
		{
			fixture.remove()
		}
		var treeReads = 0
		var reader = GitTurnBaselineManifestReader
		{
			arguments in
			if arguments.first == "ls-tree"
			{
				treeReads += 1
			}
			return try fixture.git(arguments)
		}
		let unborn = try reader.read()
		#expect(unborn.paths == ["source.txt"])
		#expect(unborn.headTree.isEmpty)
		#expect(try reader.read() == unborn)
		#expect(treeReads == 0)
		try fixture.commit()
		let committed = try reader.read()
		try fixture.git(["rm", "--cached", "--", "source.txt"])
		let deletedFromIndex = try reader.read()
		#expect(deletedFromIndex.paths == ["source.txt"])
		#expect(deletedFromIndex.index.isEmpty)
		#expect(deletedFromIndex.headTree == committed.headTree)
		#expect(treeReads == 1)
	}

	@Test func anExistingHEADWithAMissingCommitCannotBecomeAnEmptyTrackedTree() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let head = String(
			decoding: try fixture.git(["rev-parse", "--verify", "HEAD"]),
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines)
		try fixture.git(["rm", "--cached", "--", "source.txt"])
		let commitObject = fixture.root.appendingPathComponent(".git/objects")
			.appendingPathComponent(String(head.prefix(2)))
			.appendingPathComponent(String(head.dropFirst(2)))
		try FileManager.default.removeItem(at: commitObject)
		#expect(String(
			decoding: try fixture.git(["rev-parse", "--verify", "HEAD"]),
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines) == head)
		let commands = GitTurnBaselineGitCommands(
			root: fixture.root.path,
			maximumBytes: GitTurnBaselineLimits().maximumCaptureBytes
		)
		var manifests = GitTurnBaselineManifestReader(commands: commands)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try manifests.read()
		}
		let reader = GitTurnBaselineTreeReader(
			root: fixture.root.path,
			limits: GitTurnBaselineLimits()
		)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try reader.capture()
		}
	}

	@Test func cachedHEADTreesDoNotHideUnmergedIndexEntries() throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var reader = GitTurnBaselineManifestReader(runCommand: fixture.git)
		_ = try reader.read()
		let blob = String(
			decoding: try fixture.git(["rev-parse", "HEAD:source.txt"]),
			as: UTF8.self
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let conflict = "0 " + String(
			repeating: "0",
			count: 40
		) + "\tsource.txt\n"
			+ "100644 " + blob + " 1\tsource.txt\n"
			+ "100644 " + blob + " 2\tsource.txt\n"
			+ "100644 " + blob + " 3\tsource.txt\n"
		try fixture.gitWithInput(
			["update-index", "--index-info"],
			bytes: Data(conflict.utf8)
		)
		#expect(throws: GitTurnBaselineReadError.self)
		{
			try reader.read()
		}
	}

	@Test func cancellationAfterResolvingACachedTreeStillStopsTheRead() async throws
	{
		let task = Task.detached
		{
			var resolutions = 0
			let objectID = String(
				repeating: "a",
				count: 40
			)
			var reader = GitTurnBaselineManifestReader
			{
				arguments in
				if arguments.first == "rev-parse"
				{
					resolutions += 1
					if resolutions == 2
					{
						withUnsafeCurrentTask
						{
							$0?.cancel()
						}
					}
					return Data("\(objectID)\n".utf8)
				}
				let fields = arguments.first == "ls-files"
					? "100644 \(objectID) 0" : "100644 blob \(objectID)"
				return Data("\(fields)\tsource.txt\0".utf8)
			}
			_ = try reader.read()
			return try reader.read()
		}
		do
		{
			_ = try await task.value
			Issue.record("Cancellation must not be hidden by an immutable-tree cache hit.")
		}
		catch is CancellationError
		{
		}
	}
}
