import Foundation
import Testing

@testable import CodexGUI

struct GitTurnBaselineServiceTests
{
	@Test func retentionLimitIncludesSavedProvenanceAndManifestBytes() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = 128
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		let result = await service.capture(fixture.captureRequest())
		guard case .unavailable(.lastTurnBaselineUnavailable) = result
		else
		{
			Issue
				.record("Small file contents must not bypass the metadata retention limit.")
			return
		}
		let directories = try FileManager.default
			.contentsOfDirectory(atPath: fixture.storageRoot.path)
		#expect(directories.isEmpty)
	}

	@Test func pendingCaptureCannotExceedAggregateBytesOrEvictAcceptedTurn() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let initial = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(initial)
		let accepted = try await fixture.bind(
			captured,
			service: initial,
			turnID: "accepted-turn"
		)
		let manifest = fixture.storageRoot
			.appendingPathComponent(captured.identity.id.uuidString)
			.appendingPathComponent("manifest.json")
		var limits = GitTurnBaselineLimits()
		limits.maximumRetainedBytes = try Data(contentsOf: manifest).count
			+ accepted.byteCount + 1
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		guard case .unavailable(.lastTurnBaselineUnavailable) = await service.capture(
			fixture.captureRequest(threadID: "pending-chat")
		)
		else
		{
			Issue.record("A pending capture must respect the aggregate byte limit")
			return
		}
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "fixture-chat",
			turnID: "accepted-turn"
		) == accepted)
	}

	@Test func actualPreTurnBytesCancelPreexistingStagedAndUnstagedChanges() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"source.txt",
			"staged before\ncontext\n"
		)
		try fixture.git(["add", "--", "source.txt"])
		try fixture.write(
			"source.txt",
			"working before\ncontext\n"
		)
		try fixture.write(
			"staged addition.txt",
			"already added\n"
		)
		try fixture.git(["add", "--", "staged addition.txt"])
		try fixture.write(
			"untracked.txt",
			"ignored\n"
		)
		let before = try fixture.repositoryEvidence()
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(service)
		let bound = try await fixture.bind(
			captured,
			service: service,
			turnID: "actual-turn"
		)
		let empty = try await fixture.comparison(
			service,
			baseline: bound
		)
		#expect(empty.files.isEmpty)
		#expect(try fixture.repositoryEvidence() == before)
		try fixture.write(
			"source.txt",
			"changed during turn\ncontext\n"
		)
		try fixture.write(
			"untracked.txt",
			"still ignored\n"
		)
		let changed = try await fixture.comparison(
			service,
			baseline: bound
		)
		#expect(changed.files.map(\.path) == ["source.txt"])
		let patch = String(
			decoding: changed.patch,
			as: UTF8.self
		)
		#expect(patch.contains("-working before"))
		#expect(patch.contains("+changed during turn"))
		#expect(patch.contains(" context"))
		#expect(changed.additions == 1 && changed.deletions == 1)
		try fixture.write(
			"source.txt",
			"working before\ncontext\n"
		)
		try fixture.checkPatch(changed.patch)
		try fixture.write(
			"source.txt",
			"changed during turn\ncontext\n"
		)
		try fixture.git(["add", "--", "source.txt"])
		try fixture.commit()
		let afterCommit = try await fixture.comparison(
			service,
			baseline: bound
		)
		#expect(afterCommit.patch == changed.patch)
	}

	@Test func additionsDeletionsRenamesModesAndSymlinksUseRealTrackedSnapshot() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"deleted.txt",
			"deleted without newline"
		)
		try fixture.write(
			"rename from.txt",
			"stable rename\nsecond\nthird\n"
		)
		try fixture.write(
			"executable.txt",
			"mode\n"
		)
		try FileManager.default.createSymbolicLink(
			atPath: fixture.root.appendingPathComponent("link").path,
			withDestinationPath: "/neutral/before"
		)
		try fixture.git(["add", "-A"])
		try fixture.commit()
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(service)
		let bound = try await fixture.bind(
			captured,
			service: service,
			turnID: "turn"
		)
		try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("deleted.txt"))
		try FileManager.default.moveItem(
			at: fixture.root.appendingPathComponent("rename from.txt"),
			to: fixture.root.appendingPathComponent("rename to.txt")
		)
		let nestedPath = "dir/a/before/new\tname.txt"
		try fixture.write(
			nestedPath,
			"added without newline"
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: fixture.root.appendingPathComponent("executable.txt").path
		)
		try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("link"))
		try FileManager.default.createSymbolicLink(
			atPath: fixture.root.appendingPathComponent("link").path,
			withDestinationPath: "/neutral/after"
		)
		try fixture.git(["add", "-A"])
		let evidence = try fixture.repositoryEvidence()
		let comparison = try await fixture.comparison(
			service,
			baseline: bound
		)
		#expect(try fixture.repositoryEvidence() == evidence)
		#expect(comparison.files.contains
		{
			$0.path == nestedPath && $0.kind == .added
		})
		#expect(comparison.files.contains
		{
			$0.path == "deleted.txt" && $0.kind == .deleted
		})
		#expect(comparison.files.contains
		{
			$0.oldPath == "rename from.txt" && $0.newPath == "rename to.txt" && $0.kind == .renamed
		})
		let patch = String(
			decoding: comparison.patch,
			as: UTF8.self
		)
		#expect(patch.contains("old mode 100644\nnew mode 100755"))
		#expect(patch.contains("-/neutral/before"))
		#expect(patch.contains("+/neutral/after"))
		#expect(patch.contains("\\ No newline at end of file"))
		#expect(!patch.contains("a/before/deleted.txt"))
		#expect(!patch.contains("b/after/link"))
		let command = try #require(comparison.copyCommand)
		let encoded = try #require(command.components(separatedBy: "'").dropFirst(3).first)
		#expect(Data(base64Encoded: encoded) == comparison.patch)
		let savedTree = fixture.storageRoot.appendingPathComponent(bound.identity.id.uuidString)
			.appendingPathComponent("before")
		try fixture.checkPatch(
			comparison.patch,
			in: savedTree
		)
	}

	@Test func acceptedBaselineRestoresAcrossSessionsAndRejectsOtherOwners() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let first = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(first)
		let accepted = try await fixture.bind(
			captured,
			service: first,
			turnID: "persisted-turn"
		)
		try fixture.write(
			"source.txt",
			"after restart\ncontext\n"
		)
		let restored = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let reference = try #require(await restored.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "fixture-chat",
			turnID: "persisted-turn"
		))
		#expect(reference == accepted)
		var request = fixture.comparisonRequest(
			baseline: nil,
			turnID: "persisted-turn",
			sessionID: UUID()
		)
		guard case .snapshot(let snapshot) = await restored.compare(request)
		else
		{
			Issue
				.record("Persisted actual turn must restore into a fresh workspace session")
			return
		}
		#expect(snapshot.additions == 1)
		request.lastTurnBaseline = reference
		request.lastTurnID = "other-turn"
		#expect(await restored.compare(request) == .unavailable(.baselineOwnershipMismatch))
		let otherChat = fixture.comparisonRequest(
			baseline: reference,
			turnID: "persisted-turn",
			threadID: "other-chat"
		)
		#expect(await restored.compare(otherChat) == .unavailable(.baselineOwnershipMismatch))
	}

	@Test func lateBindingCannotReplaceNewerTurnAndUnboundRecordsDoNotRestore() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let earlier = try await fixture.capture(service)
		let newer = try await fixture.capture(service)
		let accepted = try await fixture.bind(
			newer,
			service: service,
			turnID: "newer-turn"
		)
		guard case .unavailable = await service.bind(
			earlier,
			turnID: "late-old-turn"
		)
		else
		{
			Issue.record("Late old binding must not replace the current chat baseline")
			return
		}
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "fixture-chat",
			turnID: "newer-turn"
		) == accepted)
		let unbound = try await fixture.capture(
			service,
			threadID: "unbound-chat"
		)
		let restored = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		#expect(await restored.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "unbound-chat",
			turnID: "fabricated-turn"
		) == nil)
		let path = fixture.storageRoot.appendingPathComponent(unbound.identity.id.uuidString)
		#expect(!FileManager.default.fileExists(atPath: path.path))
	}

	@Test func missingSavedBytesAndEvictionRemainExplicitlyUnavailable() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		var limits = GitTurnBaselineLimits()
		limits.maximumBaselines = 1
		let service = LocalGitTurnBaselineService(
			storageRoot: fixture.storageRoot,
			limits: limits
		)
		let first = try await fixture.capture(service)
		let accepted = try await fixture.bind(
			first,
			service: service,
			turnID: "turn"
		)
		let directory = fixture.storageRoot.appendingPathComponent(first.identity.id.uuidString)
		let tree = directory.appendingPathComponent("before")
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: tree.path
		)
		try FileManager.default.removeItem(at: tree.appendingPathComponent("source.txt"))
		guard case .unavailable(.lastTurnBaselineUnavailable) = await service.compare(
			fixture.comparisonRequest(
				baseline: accepted,
				turnID: "turn"
			)
		)
		else
		{
			Issue.record("Missing immutable bytes must not fall back to HEAD")
			return
		}
		let next = try await fixture.capture(
			service,
			threadID: "other-chat"
		)
		#expect(await service.lookup(
			repositoryRoot: fixture.root.path,
			threadID: "fixture-chat",
			turnID: "turn"
		) == accepted)
		_ = try await fixture.bind(
			next,
			service: service,
			turnID: "other-turn"
		)
		guard case .unavailable(.lastTurnBaselineUnavailable) = await service.compare(
			fixture.comparisonRequest(
				baseline: accepted,
				turnID: "turn"
			)
		)
		else
		{
			Issue.record("Evicted baseline must remain unavailable")
			return
		}
	}

	@Test func directoryAndSymlinkParentTransitionsNeverFollowExternalTargets() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		try fixture.write(
			"folder/child.txt",
			"old child\n"
		)
		try fixture.write(
			"becomes-folder",
			"old leaf\n"
		)
		try fixture.git(["add", "-A"])
		try fixture.commit()
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(service)
		let accepted = try await fixture.bind(
			captured,
			service: service,
			turnID: "turn"
		)
		try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("folder"))
		let external = fixture.container.appendingPathComponent("external")
		try FileManager.default.createDirectory(
			at: external,
			withIntermediateDirectories: false
		)
		try Data("external must not be read\n".utf8)
			.write(to: external.appendingPathComponent("child.txt"))
		try FileManager.default.createSymbolicLink(
			atPath: fixture.root.appendingPathComponent("folder").path,
			withDestinationPath: external.path
		)
		try FileManager.default
			.removeItem(at: fixture.root.appendingPathComponent("becomes-folder"))
		try fixture.write(
			"becomes-folder/child.txt",
			"new child\n"
		)
		try fixture.git(["add", "-A"])
		let snapshot = try await fixture.comparison(
			service,
			baseline: accepted
		)
		#expect(snapshot.files.contains
		{
			$0.path == "folder/child.txt" && $0.kind == .deleted
		})
		#expect(snapshot.files.contains
		{
			$0.path == "becomes-folder" && $0.kind == .deleted
		})
		#expect(snapshot.files
			.contains
			{
				$0.path == "becomes-folder/child.txt" && $0.kind == .added
			})
		#expect(!String(
			decoding: snapshot.patch,
			as: UTF8.self
		)
		.contains("external must not be read"))
	}

	@Test func regularToSymlinkTypeSwapHasOneNavigableFile() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(service)
		let accepted = try await fixture.bind(
			captured,
			service: service,
			turnID: "type-change"
		)
		try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("source.txt"))
		try FileManager.default.createSymbolicLink(
			atPath: fixture.root.appendingPathComponent("source.txt").path,
			withDestinationPath: "/neutral/target"
		)
		let snapshot = try await fixture.comparison(
			service,
			baseline: accepted
		)
		#expect(snapshot.files.count == 1)
		#expect(snapshot.files.first?.path == "source.txt")
		#expect(snapshot.files.first?.kind == .modified)
		#expect(snapshot.additions == 1 && snapshot.deletions == 2)
		#expect(snapshot.files.first?.hunks.count == 2)
	}

	@Test func unmergedAndGitlinkEntriesCannotProduceIncompleteBaselines() async throws
	{
		let fixture = try GitTurnBaselineFixture()
		defer
		{
			fixture.remove()
		}
		let hash = String(
			decoding: try fixture.git(["rev-parse", "HEAD"]),
			as: UTF8.self
		)
		.trimmingCharacters(in: .whitespacesAndNewlines)
		try fixture.git(["update-index", "--add", "--cacheinfo", "160000," + hash + ",module"])
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		guard case .unavailable(.lastTurnBaselineUnavailable) = await service
			.capture(fixture.captureRequest())
		else
		{
			Issue.record("Gitlinks must be explicit unsupported entries")
			return
		}
		try fixture.git(["update-index", "--force-remove", "--", "module"])
		let blob = String(
			decoding: try fixture.git(["rev-parse", "HEAD:source.txt"]),
			as: UTF8.self
		)
		.trimmingCharacters(in: .whitespacesAndNewlines)
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
		guard case .unavailable(.lastTurnBaselineUnavailable) = await service
			.capture(fixture.captureRequest())
		else
		{
			Issue.record("Unmerged index stages must be unavailable")
			return
		}
	}

	@Test func captureLimitsUnbornIndexAndConfiguredProgramsAreExplicit() async throws
	{
		let fixture = try GitTurnBaselineFixture(commitInitial: false)
		defer
		{
			fixture.remove()
		}
		try fixture.git(["config", "filter.unsafe.clean", "touch filter-ran; cat"])
		try fixture.git(["config", "core.fsmonitor", "touch monitor-ran"])
		try fixture.write(
			".gitattributes",
			"*.txt filter=unsafe\n"
		)
		let service = LocalGitTurnBaselineService(storageRoot: fixture.storageRoot)
		let captured = try await fixture.capture(service)
		#expect(captured.trackedFileCount == 1)
		#expect(!FileManager.default
			.fileExists(atPath: fixture.root.appendingPathComponent("filter-ran").path))
		#expect(!FileManager.default
			.fileExists(atPath: fixture.root.appendingPathComponent("monitor-ran").path))
		var limits = GitTurnBaselineLimits()
		limits.maximumFileBytes = 2
		let limited = LocalGitTurnBaselineService(
			storageRoot: fixture.container.appendingPathComponent("limited"),
			limits: limits
		)
		guard case .unavailable(.lastTurnBaselineUnavailable) = await limited
			.capture(fixture.captureRequest())
		else
		{
			Issue.record("Oversized file capture must fail visibly")
			return
		}
		let inside = LocalGitTurnBaselineService(storageRoot: fixture.root
			.appendingPathComponent("baselines"))
		guard case .unavailable(.lastTurnBaselineUnavailable) = await inside
			.capture(fixture.captureRequest())
		else
		{
			Issue.record("Baseline storage cannot write inside the repository")
			return
		}
	}
}
