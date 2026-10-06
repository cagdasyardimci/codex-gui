import Foundation
import Testing

@testable import CodexGUI

@Suite("Git task workspaces")
struct GitWorktreeManagerTests
{
	@Test("Captured cleanup recovery preserves removal phase and rejects a newer binding")
	func capturedCleanupRecoveryPreservesFrozenPhase() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let captured = try await manager.createCheckout(
			taskID: "locked",
			name: "Locked",
			from: fixture.source
		)
		_ = try fixture.git(
			["worktree", "lock", captured.checkoutPath],
			at: fixture.source
		)
		do
		{
			_ = try await manager.removeCheckout(expected: captured)
			Issue.record("Locked checkout was removed")
		}
		catch TaskWorkspaceError.gitFailure
		{
		}
		let scoped = try await manager.recover(preservingRemovalOf: captured)
		#expect(scoped.first
		{
			$0.workspace.id == captured.id
		}?.workspace.phase == .removing)
		#expect(try TaskWorkspaceStore(directory: fixture.records).load(id: captured.id)?
			.phase == .removing)
		let ordinary = try await manager.recover()
		#expect(ordinary.first
		{
			$0.workspace.id == captured.id
		}?.workspace.phase == .active)
		let bound = try await manager.bindThread(
			id: captured.id,
			threadID: "new-owner"
		)
		do
		{
			_ = try await manager.removeCheckout(expected: bound)
			Issue.record("Locked checkout was removed")
		}
		catch TaskWorkspaceError.gitFailure
		{
		}
		let foreign = try await manager.recover(preservingRemovalOf: captured)
		#expect(foreign.first
		{
			$0.workspace.id == captured.id
		}?.kind == .ownershipConflict)
		let durable = try TaskWorkspaceStore(directory: fixture.records).load(id: captured.id)
		#expect(durable?.threadID == "new-owner")
		#expect(durable?.phase == .removing)
	}

	@Test("Captured unbound records cannot authorize cleanup after thread binding changes")
	func capturedBindingCannotRemoveNewOwner() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let captured = try await manager.createCheckout(
			taskID: "captured",
			name: "Captured",
			from: fixture.source
		)
		let bound = try await manager.bindThread(
			id: captured.id,
			threadID: "bound-thread"
		)
		for verifyOnly in [true, false]
		{
			do
			{
				if verifyOnly
				{
					_ = try await manager.activeCheckout(expected: captured)
				}
				else
				{
					_ = try await manager.removeCheckout(expected: captured)
				}
				Issue.record("A changed binding must reject the captured record")
			}
			catch
			{
			}
		}
		#expect(FileManager.default.fileExists(atPath: bound.checkoutPath))
		#expect(try await manager.activeCheckout(expected: bound) == bound)
	}

	@Test("Captured cleanup cannot cross a changed durable lifecycle phase")
	func capturedPhaseCannotAuthorizeRemoval() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let captured = try await manager.createCheckout(
			taskID: "phase",
			name: "Phase",
			from: fixture.source
		)
		var removing = captured
		removing.phase = .removing
		try TaskWorkspaceStore(directory: fixture.records).save(removing)
		do
		{
			_ = try await manager.removeCheckout(expected: captured)
			Issue.record("Changed phase must reject captured cleanup")
		}
		catch
		{
		}
		#expect(FileManager.default.fileExists(atPath: captured.checkoutPath))
		#expect(try TaskWorkspaceStore(directory: fixture.records).load(id: captured.id)?
			.phase == .removing)
	}

	@Test("Expected-record removal rechecks dirty files and cancelled authority")
	func expectedRemovalRechecksFilesAndCancellation() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let captured = try await manager.createCheckout(
			taskID: "fresh-check",
			name: "Fresh check",
			from: fixture.source
		)
		_ = try await manager.activeCheckout(expected: captured)
		let added = URL(fileURLWithPath: captured.checkoutPath).appendingPathComponent("late.txt")
		try "Added after verification".write(
			to: added,
			atomically: true,
			encoding: .utf8
		)
		do
		{
			_ = try await manager.removeCheckout(expected: captured)
			Issue.record("Late dirt must block removal")
		}
		catch
		{
		}
		#expect(FileManager.default.fileExists(atPath: added.path))
		try FileManager.default.removeItem(at: added)
		let removal = Task
		{
			withUnsafeCurrentTask
			{
				$0?.cancel()
			}
			return try await manager.removeCheckout(expected: captured)
		}
		if case .success = await removal.result
		{
			Issue.record("Cancelled cleanup authority must not remove files")
		}
		#expect(FileManager.default.fileExists(atPath: captured.checkoutPath))
		let removed = try await manager.removeCheckout(expected: captured)
		#expect(removed.phase == .checkoutRemoved)
		#expect(try fixture.git(
			["rev-parse", captured.branch],
			at: fixture.source
		) == captured.baseCommit)
	}

	@Test("Dirty source stays untouched and task branches and paths are unique")
	func dirtySourceIsPreserved() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		try "staged\n".write(
			to: fixture.source.appendingPathComponent("tracked.txt"),
			atomically: true,
			encoding: .utf8
		)
		_ = try fixture.git(
			["add", "tracked.txt"],
			at: fixture.source
		)
		try "staged and unstaged\n".write(
			to: fixture.source.appendingPathComponent("tracked.txt"),
			atomically: true,
			encoding: .utf8
		)
		try "untracked\n".write(
			to: fixture.source.appendingPathComponent("notes.txt"),
			atomically: true,
			encoding: .utf8
		)
		let originalStatus = try fixture.git(
			["status", "--porcelain=v1", "--untracked-files=all"],
			at: fixture.source
		)

		let manager = fixture.manager()
		let first = try await manager.createCheckout(
			taskID: "task-one",
			name: "Review parser",
			from: fixture.source
		)
		let second = try await manager.createCheckout(
			taskID: "task-two",
			name: "Review parser",
			from: fixture.source
		)

		#expect(first.phase == .active)
		#expect(first.sourceWasDirty)
		#expect(first.sourceProjectPath == fixture.source.path)
		#expect(first.branch != second.branch)
		#expect(first.checkoutPath != second.checkoutPath)
		#expect(first.branch.hasPrefix("codex/task/review-parser-"))
		#expect(try fixture.git(
			["rev-parse", "HEAD"],
			at: fixture.source
		) == first.baseCommit)
		#expect(
			try fixture.git(
				["rev-parse", "HEAD"],
				at: URL(fileURLWithPath: first.checkoutPath)
			)
				== first.baseCommit
		)
		#expect(
			try String(
				contentsOf: URL(fileURLWithPath: first.checkoutPath)
					.appendingPathComponent("tracked.txt"),
				encoding: .utf8
			) == "committed\n"
		)
		#expect(
			try fixture.git(
				["status", "--porcelain=v1", "--untracked-files=all"],
				at: fixture.source
			) == originalStatus
		)
		#expect(
			try String(
				contentsOf: fixture.source.appendingPathComponent("tracked.txt"),
				encoding: .utf8
			) == "staged and unstaged\n"
		)
		#expect(
			try fixture.git(
				["status", "--porcelain=v1"],
				at: URL(fileURLWithPath: first.checkoutPath)
			).isEmpty
		)
		#expect(try TaskWorkspaceStore(directory: fixture.records).loadAll().count == 2)
	}

	@Test("Changed branch blocks checkout use and removal")
	func changedBranchBlocksCheckoutUseAndRemoval() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let workspace = try await manager.createCheckout(
			taskID: "cleanup-task",
			name: "Clean checkout",
			from: fixture.source
		)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)

		_ = try fixture.git(
			["switch", "-c", "unrelated-branch"],
			at: checkout
		)
		do
		{
			_ = try await manager.activeCheckout(id: workspace.id)
			Issue.record("A changed checkout was accepted for a turn")
		}
		catch TaskWorkspaceError.ownershipConflict
		{
			#expect(FileManager.default.fileExists(atPath: checkout.path))
		}
		do
		{
			_ = try await manager.removeCheckout(id: workspace.id)
			Issue.record("Cleanup accepted a checkout on a different branch")
		}
		catch TaskWorkspaceError.ownershipConflict
		{
			#expect(FileManager.default.fileExists(atPath: checkout.path))
		}
		_ = try fixture.git(
			["switch", workspace.branch],
			at: checkout
		)
		#expect(try await manager.activeCheckout(id: workspace.id).branch == workspace.branch)
	}

	@Test("Untracked user files block checkout removal")
	func untrackedUserFileBlocksCheckoutRemoval() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let workspace = try await manager.createCheckout(
			taskID: "cleanup-task",
			name: "Clean checkout",
			from: fixture.source
		)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)

		let userFile = checkout.appendingPathComponent("user-work.txt")
		try "keep\n".write(
			to: userFile,
			atomically: true,
			encoding: .utf8
		)
		do
		{
			_ = try await manager.removeCheckout(id: workspace.id)
			Issue.record("Cleanup accepted a dirty checkout")
		}
		catch TaskWorkspaceError.dirtyCheckout
		{
			#expect(try String(
				contentsOf: userFile,
				encoding: .utf8
			) == "keep\n")
		}
		#expect(
			try TaskWorkspaceStore(directory: fixture.records).load(id: workspace.id)?.phase
				== .active
		)
	}

	@Test("Ignored user files block checkout removal")
	func ignoredUserFileBlocksCheckoutRemoval() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let workspace = try await manager.createCheckout(
			taskID: "cleanup-task",
			name: "Clean checkout",
			from: fixture.source
		)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)

		try "generated/\n".write(
			to: fixture.source.appendingPathComponent(".git/info/exclude"),
			atomically: true,
			encoding: .utf8
		)
		let ignored = checkout.appendingPathComponent(
			"generated/cache",
			isDirectory: false
		)
		try FileManager.default.createDirectory(
			at: ignored.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try "keep ignored\n".write(
			to: ignored,
			atomically: true,
			encoding: .utf8
		)
		#expect(try fixture.git(
			["status", "--porcelain=v1"],
			at: checkout
		).isEmpty)
		do
		{
			_ = try await manager.removeCheckout(id: workspace.id)
			Issue.record("Cleanup accepted an ignored user file")
		}
		catch TaskWorkspaceError.dirtyCheckout
		{
			#expect(try String(
				contentsOf: ignored,
				encoding: .utf8
			) == "keep ignored\n")
		}
	}

	@Test("Clean cleanup retains the branch and durable removal phase")
	func cleanupIsSafe() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let workspace = try await manager.createCheckout(
			taskID: "cleanup-task",
			name: "Clean checkout",
			from: fixture.source
		)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)

		let closed = try await manager.removeCheckout(id: workspace.id)
		#expect(closed.phase == .checkoutRemoved)
		#expect(!FileManager.default.fileExists(atPath: checkout.path))
		#expect(
			try fixture.git(
				["show-ref", "--verify", "refs/heads/\(workspace.branch)"],
				at: fixture.source
			).contains(workspace.baseCommit)
		)
		#expect(
			try TaskWorkspaceStore(directory: fixture.records).load(id: workspace.id)?.phase
				== .checkoutRemoved
		)
	}

	@Test("A clean checkout with commits retains those commits on its branch")
	func committedWorkSurvivesCheckoutRemoval() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let workspace = try await manager.createCheckout(
			taskID: "committed-work",
			name: "Preserve commits",
			from: fixture.source
		)
		let checkout = URL(fileURLWithPath: workspace.checkoutPath)
		try "new committed content\n".write(
			to: checkout.appendingPathComponent("tracked.txt"),
			atomically: true,
			encoding: .utf8
		)
		_ = try fixture.git(
			["commit", "-qam", "Keep this commit"],
			at: checkout
		)
		let commit = try fixture.git(
			["rev-parse", "HEAD"],
			at: checkout
		)

		_ = try await manager.removeCheckout(id: workspace.id)
		#expect(try fixture.git(
			["rev-parse", workspace.branch],
			at: fixture.source
		) == commit)
		#expect(
			try fixture.git(
				["show", "\(workspace.branch):tracked.txt"],
				at: fixture.source
			) == "new committed content"
		)
	}

	@Test("A failing checkout hook leaves a recoverable intent record")
	func partialGitFailureIsRecovered() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let hook = fixture.source.appendingPathComponent(".git/hooks/post-checkout")
		try "#!/bin/sh\nexit 1\n".write(
			to: hook,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: hook.path
		)
		let manager = fixture.manager()

		do
		{
			_ = try await manager.createCheckout(
				taskID: "failed-hook",
				name: "Interrupted add",
				from: fixture.source
			)
			Issue.record("The failing hook should report a Git error")
		}
		catch TaskWorkspaceError.gitFailure
		{
			let pending = try #require(TaskWorkspaceStore(directory: fixture.records).loadAll()
				.first)
			#expect(pending.phase == .preparing)
			#expect(FileManager.default.fileExists(atPath: pending.checkoutPath))
			let recovered = try await manager.recover()
			#expect(recovered.count == 1)
			#expect(recovered.first?.kind == .active)
			#expect(recovered.first?.workspace.phase == .active)
			#expect(
				try TaskWorkspaceStore(directory: fixture.records).load(id: pending.id)?.phase
					== .active
			)
		}
	}

	@Test("Recovery completes an interrupted removal without deleting the branch")
	func interruptedRemovalIsRecovered() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		var workspace = try await manager.createCheckout(
			taskID: "crashed-removal",
			name: "Crash recovery",
			from: fixture.source
		)
		workspace.phase = .removing
		try TaskWorkspaceStore(directory: fixture.records).save(workspace)
		_ = try fixture.git(
			["worktree", "remove", workspace.checkoutPath],
			at: fixture.source
		)

		let recovered = try await fixture.manager().recover()
		#expect(recovered.first?.kind == .checkoutRemoved)
		#expect(recovered.first?.workspace.phase == .checkoutRemoved)
		#expect(
			try fixture.git(
				["show-ref", "--verify", "refs/heads/\(workspace.branch)"],
				at: fixture.source
			).contains(workspace.baseCommit)
		)
	}

	@Test("Incomplete creation is reported and only its unchanged branch can be cancelled")
	func incompleteCreationCanBeCancelled() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let workspace = try fixture.preparationRecord(taskID: "never-added")
		_ = try fixture.git(
			["branch", workspace.branch, workspace.baseCommit],
			at: fixture.source
		)
		let manager = fixture.manager()

		#expect(try await manager.recover().first?.kind == .creationInterrupted)
		let cancelled = try await manager.cancelIncompleteCreation(id: workspace.id)
		#expect(cancelled.phase == .creationCancelled)
		#expect(try fixture.git(
			["branch", "--list", workspace.branch],
			at: fixture.source
		).isEmpty)
		#expect(
			try TaskWorkspaceStore(directory: fixture.records).load(id: workspace.id)?.phase
				== .creationCancelled
		)
	}

	@Test("Two managers cannot assign two checkouts to one task")
	func taskOwnershipIsUniqueAcrossManagers() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let firstManager = fixture.manager()
		let secondManager = fixture.manager()
		let first = Task
		{
			try await firstManager.createCheckout(
				taskID: "shared-task",
				name: "First",
				from: fixture.source
			)
		}
		let second = Task
		{
			try await secondManager.createCheckout(
				taskID: "shared-task",
				name: "Second",
				from: fixture.source
			)
		}
		let results = [await first.result, await second.result]
		#expect(
			results.filter
			{
				if case .success = $0
				{
					return true
				}
				return false
			}.count == 1
		)
		#expect(
			results.filter
			{
				if case .failure = $0
				{
					return true
				}
				return false
			}.count == 1
		)
		#expect(try TaskWorkspaceStore(directory: fixture.records).loadAll().count == 1)
		#expect(
			try fixture.git(
				["worktree", "list", "--porcelain"],
				at: fixture.source
			).components(separatedBy: "worktree ").count == 3
		)
	}

	@Test("A backend conversation can bind to only one task checkout")
	func threadBindingIsDurableAndUnique() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let manager = fixture.manager()
		let first = try await manager.createCheckout(
			taskID: "first-task",
			name: "First task",
			from: fixture.source
		)
		let second = try await manager.createCheckout(
			taskID: "second-task",
			name: "Second task",
			from: fixture.source
		)

		let bound = try await manager.bindThread(
			id: first.id,
			threadID: "thread-one"
		)
		#expect(bound.threadID == "thread-one")
		#expect(
			try await manager.bindThread(
				id: first.id,
				threadID: "thread-one"
			).threadID
				== "thread-one"
		)
		do
		{
			_ = try await manager.bindThread(
				id: first.id,
				threadID: "thread-two"
			)
			Issue.record("A task was rebound to a different conversation")
		}
		catch TaskWorkspaceError.ownershipConflict
		{
			#expect(
				try TaskWorkspaceStore(directory: fixture.records).load(id: first.id)?.threadID
					== "thread-one"
			)
		}
		do
		{
			_ = try await manager.bindThread(
				id: second.id,
				threadID: "thread-one"
			)
			Issue.record("Two tasks were bound to one conversation")
		}
		catch TaskWorkspaceError.threadAlreadyOwned("thread-one")
		{
			#expect(
				try TaskWorkspaceStore(directory: fixture.records).load(id: second.id)?.threadID
					== nil
			)
		}
		#expect(try await fixture.manager().recover().first?.workspace.threadID == "thread-one")
	}

	@Test("A checkout root inside the source is rejected before making files")
	func checkoutRootInsideSourceIsRejected() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let nested = fixture.source.appendingPathComponent(
			"new-checkouts",
			isDirectory: true
		)
		let manager = GitWorktreeManager(
			recordDirectory: fixture.records,
			checkoutRoot: nested
		)
		let before = try fixture.git(
			["status", "--porcelain=v1"],
			at: fixture.source
		)

		do
		{
			_ = try await manager.createCheckout(
				taskID: "unsafe-path",
				name: "Unsafe path",
				from: fixture.source
			)
			Issue.record("A nested worktree root should be rejected")
		}
		catch TaskWorkspaceError.checkoutRootInsideSource
		{
			#expect(!FileManager.default.fileExists(atPath: nested.path))
			#expect(try fixture.git(
				["status", "--porcelain=v1"],
				at: fixture.source
			) == before)
			#expect(try TaskWorkspaceStore(directory: fixture.records).loadAll().isEmpty)
		}
	}

	@Test("Unsupported ownership records are preserved and block operations")
	func unsupportedRecordIsPreserved() throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let workspace = try fixture.preparationRecord(taskID: "future-format")
		let file = fixture.records.appendingPathComponent(
			"\(workspace.id.uuidString.lowercased()).json"
		)
		var document = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: file))
				as? [String: Any]
		)
		document["version"] = 2
		let future = try JSONSerialization.data(
			withJSONObject: document,
			options: [.sortedKeys]
		)
		try future.write(
			to: file,
			options: .atomic
		)

		do
		{
			_ = try TaskWorkspaceStore(directory: fixture.records).loadAll()
			Issue.record("A newer record version should not be interpreted")
		}
		catch TaskWorkspaceError.unsupportedRecordVersion(2)
		{
			#expect(try Data(contentsOf: file) == future)
		}
	}

	@Test("A changed ownership record cannot delete its branch")
	func tamperedRecordCannotDeleteBranch() async throws
	{
		let fixture = try GitFixture()
		defer
		{
			fixture.remove()
		}
		let workspace = try fixture.preparationRecord(taskID: "changed-record")
		_ = try fixture.git(
			["branch", workspace.branch, workspace.baseCommit],
			at: fixture.source
		)
		let file = fixture.records.appendingPathComponent(
			"\(workspace.id.uuidString.lowercased()).json"
		)
		var document = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: file))
				as? [String: Any]
		)
		var owner = try #require(document["workspace"] as? [String: Any])
		owner["checkoutPath"] = fixture.root.appendingPathComponent("different-path").path
		document["workspace"] = owner
		try JSONSerialization.data(withJSONObject: document).write(
			to: file,
			options: .atomic
		)

		do
		{
			_ = try await fixture.manager().cancelIncompleteCreation(id: workspace.id)
			Issue.record("A changed record removed its branch")
		}
		catch TaskWorkspaceError.ownershipConflict
		{
			#expect(
				try fixture.git(
					["rev-parse", workspace.branch],
					at: fixture.source
				)
					== workspace.baseCommit
			)
			#expect(try await fixture.manager().recover().first?.kind == .ownershipConflict)
		}
	}
}

private struct GitFixture
{
	let root: URL
	let source: URL
	let records: URL
	let checkouts: URL

	init() throws
	{
		let rawRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
			"CodexGUI-WorktreeTests-\(UUID().uuidString)",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: rawRoot,
			withIntermediateDirectories: true
		)
		root = rawRoot.standardizedFileURL.resolvingSymlinksInPath()
		source = root.appendingPathComponent(
			"source",
			isDirectory: true
		)
		records = root.appendingPathComponent(
			"records",
			isDirectory: true
		)
		checkouts = root.appendingPathComponent(
			"checkouts",
			isDirectory: true
		)
		try prepareSourceRepository()
	}

	private func prepareSourceRepository() throws
	{
		try FileManager.default.createDirectory(
			at: source,
			withIntermediateDirectories: true
		)
		_ = try git(
			["init", "-q"],
			at: source
		)
		_ = try git(
			["config", "user.name", "Workspace Test"],
			at: source
		)
		_ = try git(
			["config", "user.email", "workspace@example.test"],
			at: source
		)
		try "committed\n".write(
			to: source.appendingPathComponent("tracked.txt"),
			atomically: true,
			encoding: .utf8
		)
		_ = try git(
			["add", "tracked.txt"],
			at: source
		)
		_ = try git(
			["commit", "-qm", "Initial commit"],
			at: source
		)
	}

	func manager() -> GitWorktreeManager
	{
		GitWorktreeManager(
			recordDirectory: records,
			checkoutRoot: checkouts
		)
	}

	func preparationRecord(taskID: String) throws -> TaskWorkspace
	{
		let id = UUID()
		let name = "\(taskID)-\(id.uuidString.lowercased())"
		let workspace = TaskWorkspace(
			id: id,
			taskID: taskID,
			threadID: nil,
			sourceProjectPath: source.path,
			repositoryGitDirectory: source.appendingPathComponent(".git").path,
			branch: "codex/task/\(name)",
			checkoutPath: checkouts.appendingPathComponent(name).path,
			baseCommit: try git(
				["rev-parse", "HEAD"],
				at: source
			),
			sourceWasDirty: false,
			createdAt: Date(),
			phase: .preparing
		)
		try TaskWorkspaceStore(directory: records).save(workspace)
		return workspace
	}

	func git(
		_ arguments: [String],
		at directory: URL
	) throws -> String
	{
		let result = try GitTestCommandRunner.run(
			in: directory,
			arguments: arguments,
			captureStandardError: true
		)
		let text = String(
			decoding: result.output,
			as: UTF8.self
		).trimmingCharacters(in: .newlines)
		guard result.terminationStatus == 0
		else
		{
			throw TaskWorkspaceError.gitFailure("git \(arguments): \(text)")
		}
		return text
	}

	func remove()
	{
		try? FileManager.default.removeItem(at: root)
	}
}
