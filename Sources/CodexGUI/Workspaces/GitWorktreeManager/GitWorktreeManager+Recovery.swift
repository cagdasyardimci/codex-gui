import Foundation

extension GitWorktreeManager
{
	/// Reconciles interrupted transitions and reports cases that need inspection.
	func recover() throws -> [TaskWorkspaceRecovery]
	{
		try store.withExclusiveLock
		{
			try recoverLocked()
		}
	}

	/// A live cleanup keeps its frozen removal phase; a changed durable owner is never adopted.
	func recover(preservingRemovalOf expected: TaskWorkspace) throws -> [TaskWorkspaceRecovery]
	{
		try store.withExclusiveLock
		{
			try store.loadAll().map
			{
				stored in
				guard stored.id == expected.id
				else
				{
					return try recoverWorkspace(stored)
				}
				guard stored.hasSameOwnership(as: expected), stored.threadID == expected.threadID,
						stored.phase == .active || stored.phase == .removing || stored
						.phase == .checkoutRemoved
				else
				{
					return TaskWorkspaceRecovery(
						workspace: stored,
						kind: .ownershipConflict
					)
				}
				return try recoverWorkspace(
					stored,
					preservingRemovalPhase: true
				)
			}
		}
	}

	private func recoverLocked() throws -> [TaskWorkspaceRecovery]
	{
		try store.loadAll().map
		{
			try recoverWorkspace($0)
		}
	}

	func recoverWorkspace(
		_ stored: TaskWorkspace,
		preservingRemovalPhase: Bool = false
	) throws -> TaskWorkspaceRecovery
	{
		var workspace = stored
		guard (try? validateManagedIdentity(of: workspace)) != nil
		else
		{
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: .ownershipConflict
			)
		}
		let source = sourceURL(for: workspace)
		let pathPresent = pathExists(workspace.checkoutPath)
		let registered = try isRegistered(
			workspace.checkoutPath,
			at: source
		)

		switch workspace.phase
		{
		case .preparing:
			guard pathPresent
			else
			{
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .creationInterrupted
				)
			}
			guard registered, (try? verifyOwnership(of: workspace)) != nil
			else
			{
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .ownershipConflict
				)
			}
			workspace.phase = .active
			try store.save(workspace)
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: .active
			)
		case .active:
			guard pathPresent
			else
			{
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .missingCheckout
				)
			}
			guard registered, (try? verifyOwnership(of: workspace)) != nil
			else
			{
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .ownershipConflict
				)
			}
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: .active
			)
		case .removing:
			if !pathPresent && !registered
			{
				workspace.phase = .checkoutRemoved
				try store.save(workspace)
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .checkoutRemoved
				)
			}
			guard pathPresent, registered, (try? verifyOwnership(of: workspace)) != nil
			else
			{
				return TaskWorkspaceRecovery(
					workspace: workspace,
					kind: .ownershipConflict
				)
			}
			// A failed or interrupted removal left this verified checkout in place.
			// Make it openable again so its conversation can be reconciled before retrying.
			if !preservingRemovalPhase
			{
				workspace.phase = .active
				try store.save(workspace)
			}
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: .removalInterrupted
			)
		case .checkoutRemoved:
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: pathPresent || registered ? .ownershipConflict : .checkoutRemoved
			)
		case .creationCancelled:
			return TaskWorkspaceRecovery(
				workspace: workspace,
				kind: pathPresent || registered ? .ownershipConflict : .creationCancelled
			)
		}
	}

}
