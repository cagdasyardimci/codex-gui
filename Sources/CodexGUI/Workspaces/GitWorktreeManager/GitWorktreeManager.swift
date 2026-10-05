import Foundation

/// Git is authoritative for checkout ownership; the record is the task's durable intent.
actor GitWorktreeManager
{
	let store: TaskWorkspaceStore
	let checkoutRoot: URL
	let fileManager: FileManager

	init(
		recordDirectory: URL = TaskWorkspaceLocations().records,
		checkoutRoot: URL = TaskWorkspaceLocations().checkouts,
		fileManager: FileManager = .default
	)
	{
		store = TaskWorkspaceStore(
			directory: recordDirectory,
			fileManager: fileManager
		)
		self.checkoutRoot = checkoutRoot
		self.fileManager = fileManager
	}

	/// Starts from committed HEAD. Staged, unstaged, and untracked source files remain in source.
	func createCheckout(
		taskID: String,
		name: String,
		from project: URL
	) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			try createCheckoutLocked(
				taskID: taskID,
				name: name,
				from: project
			)
		}
	}

	private func createCheckoutLocked(
		taskID: String,
		name: String,
		from project: URL
	) throws -> TaskWorkspace
	{
		let owner = try availableTaskOwner(taskID)
		let source = try inspectSourceRepository(at: project)
		let root = try prepareCheckoutRoot(for: source)
		var workspace = try preparingWorkspace(
			taskID: owner,
			name: name,
			source: source,
			root: root
		)
		try store.save(workspace)

		// A failing hook can return an error after Git has made the checkout. Keep the
		// preparation record so recovery can adopt the verified checkout.
		_ = try gitOutput(
			[
				"worktree",
				"add",
				"-b",
				workspace.branch,
				workspace.checkoutPath,
				workspace.baseCommit
			],
			at: source.checkout
		)
		try verifyOwnership(of: workspace)
		workspace.phase = .active
		try store.save(workspace)
		return workspace
	}

	private func availableTaskOwner(_ taskID: String) throws -> String
	{
		let owner = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !owner.isEmpty
		else
		{
			throw TaskWorkspaceError.invalidTaskID
		}
		guard try !store.loadAll().contains(where:
			{
				$0.taskID == owner
			})
		else
		{
			throw TaskWorkspaceError.taskAlreadyHasWorkspace(owner)
		}

		return owner
	}

	private func inspectSourceRepository(at project: URL) throws -> CheckoutSource
	{
		let sourcePath = try gitOutput(
			["rev-parse", "--show-toplevel"],
			at: project
		)
		let source = canonicalURL(for: URL(fileURLWithPath: sourcePath))
		let gitDirectoryPath = try gitOutput(
			["rev-parse", "--path-format=absolute", "--git-common-dir"],
			at: source
		)
		let gitDirectory = canonicalURL(for: URL(fileURLWithPath: gitDirectoryPath))
		let baseCommit = try gitOutput(
			["rev-parse", "--verify", "HEAD^{commit}"],
			at: source
		)
		let sourceWasDirty = try !gitOutput(
			["status", "--porcelain=v1", "--untracked-files=all"],
			at: source
		).isEmpty

		return CheckoutSource(
			checkout: source,
			gitDirectory: gitDirectory,
			baseCommit: baseCommit,
			wasDirty: sourceWasDirty
		)
	}

	private func prepareCheckoutRoot(for source: CheckoutSource) throws -> URL
	{
		let occupiedRoots = try worktreePaths(at: source.checkout)
		let proposedRoot = canonicalURL(for: checkoutRoot)
		guard
			isSafeCheckoutRoot(
				proposedRoot.path,
				worktreePaths: occupiedRoots,
				gitDirectory: source.gitDirectory.path
			)
		else
		{
			throw TaskWorkspaceError.checkoutRootInsideSource
		}
		try fileManager.createDirectory(
			at: checkoutRoot,
			withIntermediateDirectories: true
		)
		let root = canonicalURL(for: checkoutRoot)
		guard
			isSafeCheckoutRoot(
				root.path,
				worktreePaths: occupiedRoots,
				gitDirectory: source.gitDirectory.path
			)
		else
		{
			throw TaskWorkspaceError.checkoutRootInsideSource
		}

		return root
	}

	private func preparingWorkspace(
		taskID: String,
		name: String,
		source: CheckoutSource,
		root: URL
	) throws -> TaskWorkspace
	{
		let id = UUID()
		let slug = Self.slug(from: name)
		let suffix = id.uuidString.lowercased()
		let branch = "codex/task/\(slug)-\(suffix)"
		let checkout = root.appendingPathComponent(
			"\(slug)-\(suffix)",
			isDirectory: true
		)
		guard !pathExists(checkout.path)
		else
		{
			throw TaskWorkspaceError.checkoutPathOccupied(checkout.path)
		}
		guard try !branchExists(
			branch,
			at: source.checkout
		)
		else
		{
			throw TaskWorkspaceError.ownershipConflict("branch \(branch) already exists")
		}

		return TaskWorkspace(
			id: id,
			taskID: taskID,
			threadID: nil,
			sourceProjectPath: source.checkout.path,
			repositoryGitDirectory: source.gitDirectory.path,
			branch: branch,
			checkoutPath: checkout.path,
			baseCommit: source.baseCommit,
			sourceWasDirty: source.wasDirty,
			createdAt: Date(),
			phase: .preparing
		)
	}

	/// Persists the app-server identity after a conversation is created in this checkout.
	func bindThread(
		id: UUID,
		threadID: String
	) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			guard var workspace = try store.load(id: id)
			else
			{
				throw TaskWorkspaceError.workspaceNotFound(id)
			}
			guard workspace.phase == .active
			else
			{
				throw TaskWorkspaceError.invalidPhase(workspace.phase)
			}
			let backendID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !backendID.isEmpty
			else
			{
				throw TaskWorkspaceError.invalidThreadID
			}
			guard workspace.threadID == nil || workspace.threadID == backendID
			else
			{
				throw TaskWorkspaceError.ownershipConflict(
					"task \(workspace.taskID) has another conversation"
				)
			}
			guard
				try !store.loadAll().contains(where:
					{
						$0.id != workspace.id && $0.threadID == backendID
					})
			else
			{
				throw TaskWorkspaceError.threadAlreadyOwned(backendID)
			}
			try verifyOwnership(of: workspace)
			workspace.threadID = backendID
			try store.save(workspace)
			return workspace
		}
	}

	/// Call before sending a turn so a moved or replaced checkout cannot receive work.
	func activeCheckout(id: UUID) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			guard let workspace = try store.load(id: id)
			else
			{
				throw TaskWorkspaceError.workspaceNotFound(id)
			}
			guard workspace.phase == .active
			else
			{
				throw TaskWorkspaceError.invalidPhase(workspace.phase)
			}
			try verifyOwnership(of: workspace)
			return workspace
		}
	}

	/// Rechecks the captured binding and phase while holding the same durable ownership lock.
	func activeCheckout(expected: TaskWorkspace) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			let workspace = try expectedRecord(expected)
			guard workspace.phase == .active
			else
			{
				throw TaskWorkspaceError.invalidPhase(workspace.phase)
			}
			try verifyOwnership(of: workspace)
			return workspace
		}
	}

	func removeCheckout(expected: TaskWorkspace) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			_ = try expectedRecord(expected)
			try Task.checkCancellation()
			return try removeCheckoutLocked(
				id: expected.id,
				checksCancellation: true
			)
		}
	}

	func cancelIncompleteCreation(expected: TaskWorkspace) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			_ = try expectedRecord(expected)
			try Task.checkCancellation()
			return try cancelIncompleteCreationLocked(id: expected.id)
		}
	}

	private func expectedRecord(_ expected: TaskWorkspace) throws -> TaskWorkspace
	{
		guard let actual = try store.load(id: expected.id)
		else
		{
			throw TaskWorkspaceError.workspaceNotFound(expected.id)
		}
		guard actual.hasSameOwnership(as: expected), actual.threadID == expected.threadID,
				actual.phase == expected.phase
		else
		{
			throw TaskWorkspaceError.ownershipConflict("captured workspace record changed")
		}
		return actual
	}

	/// Removes only this verified, clean checkout. Its branch and ownership record remain.
	func removeCheckout(id: UUID) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			try removeCheckoutLocked(id: id)
		}
	}

	private func removeCheckoutLocked(
		id: UUID,
		checksCancellation: Bool = false
	) throws -> TaskWorkspace
	{
		guard var workspace = try store.load(id: id)
		else
		{
			throw TaskWorkspaceError.workspaceNotFound(id)
		}
		if workspace.phase == .checkoutRemoved
		{
			return workspace
		}
		guard workspace.phase == .active || workspace.phase == .removing
		else
		{
			throw TaskWorkspaceError.invalidPhase(workspace.phase)
		}
		try verifyOwnership(of: workspace)
		guard try !isDirty(
			workspace.checkoutPath,
			includeIgnored: true
		)
		else
		{
			throw TaskWorkspaceError.dirtyCheckout(workspace.checkoutPath)
		}

		if checksCancellation
		{
			try Task.checkCancellation()
		}
		workspace.phase = .removing
		try store.save(workspace)
		_ = try gitOutput(
			["worktree", "remove", workspace.checkoutPath],
			at: sourceURL(for: workspace)
		)
		workspace.phase = .checkoutRemoved
		try store.save(workspace)
		return workspace
	}

	/// Cancels an incomplete creation only when its branch still points at the base commit.
	func cancelIncompleteCreation(id: UUID) throws -> TaskWorkspace
	{
		try store.withExclusiveLock
		{
			try cancelIncompleteCreationLocked(id: id)
		}
	}

	private func cancelIncompleteCreationLocked(id: UUID) throws -> TaskWorkspace
	{
		guard var workspace = try store.load(id: id)
		else
		{
			throw TaskWorkspaceError.workspaceNotFound(id)
		}
		guard workspace.phase == .preparing
		else
		{
			throw TaskWorkspaceError.invalidPhase(workspace.phase)
		}
		try validateManagedIdentity(of: workspace)
		let source = sourceURL(for: workspace)
		guard !pathExists(workspace.checkoutPath),
				try !isRegistered(
				workspace.checkoutPath,
				at: source
				),
				try !isBranchCheckedOut(
				workspace.branch,
				at: source
				)
		else
		{
			throw TaskWorkspaceError.unsafeBranchRemoval(workspace.branch)
		}
		if try branchExists(
			workspace.branch,
			at: source
		)
		{
			let tip = try gitOutput(
				["rev-parse", "--verify", "refs/heads/\(workspace.branch)"],
				at: source
			)
			guard tip == workspace.baseCommit
			else
			{
				throw TaskWorkspaceError.unsafeBranchRemoval(workspace.branch)
			}
			_ = try gitOutput(
				["branch", "-D", workspace.branch],
				at: source
			)
		}
		workspace.phase = .creationCancelled
		try store.save(workspace)
		return workspace
	}

}

private struct CheckoutSource
{
	let checkout: URL
	let gitDirectory: URL
	let baseCommit: String
	let wasDirty: Bool
}
