import Foundation

extension WorkspaceCoordinatorReducer
{
	static func reduceRecovery(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		switch action
		{
		case .recoveryRequested(let request):
			guard (model.acceptsNewWork || request.cleanup != nil),
					request.recordsRevision == model.recordsRevision,
					model.pendingRecovery?.cleanup == nil
			else
			{
				return []
			}
			model.pendingRecovery = request
			effects.append(.git(.recover(request)))
		case .recoveryFinished(
			let request,
			let result
		):
			guard model.pendingRecovery == request
			else
			{
				return []
			}
			model.pendingRecovery = nil
			guard request.recordsRevision == model.recordsRevision
			else
			{
				return []
			}
			switch result
			{
			case .succeeded(let records):
				return acceptRecoveredRecords(
					records,
					model: &model
				)
			case .failed(let failure):
				model.message = "Could not read task workspaces: \(failure.message)"
			}
		default:
			return []
		}
		return effects
	}

	private static func acceptRecoveredRecords(
		_ records: [TaskWorkspaceRecovery],
		model: inout WorkspaceCoordinatorModel
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		guard Set(records.map
		{
			$0.workspace.id
		}).count == records.count
		else
		{
			return []
		}
		let recoveredByID = Dictionary(uniqueKeysWithValues: records.map
		{
			(
				$0.workspace.id,
				$0.workspace
			)
		})
		// Validate all registered owners before changing records or leases.
		let conflicts = recoveryConflicts(
			records,
			recoveredByID: recoveredByID,
			model: model
		)
		if !conflicts.isEmpty
		{
			return rejectRecoveryConflicts(
				conflicts,
				model: &model
			)
		}
		effects += reconcileRecoveredOwners(
			recoveredByID,
			model: &model
		)
		recordRecoveredSnapshot(
			records,
			model: &model
		)
		return effects
	}

	private static func rejectRecoveryConflicts(
		_ conflicts: [(WorkspaceLifecycleOwnerReference, TaskWorkspace)],
		model: inout WorkspaceCoordinatorModel
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		for (reference, expected) in conflicts
		{
			let transition = model.pendingCleanup[expected.id]
			let cleanup = transition?.stage == .recovering && transition?.request
				.expected == expected ? transition?.request : nil
			model.recoveryIssues[expected.id] = .ownershipConflict
			effects.append(.managedRecordRecoveryConflicted(
				reference,
				expected: expected,
				cleanup: cleanup,
				message: "This task workspace's saved ownership changed. " +
					"Its active connection cannot adopt another conversation."
			))
			if let cleanup
			{
				model.pendingCleanup.removeValue(forKey: expected.id)
				effects.append(.releaseCleanup(cleanup))
			}
		}
		model.recordsRevision += 1
		return effects
	}

	private static func recordRecoveredSnapshot(
		_ records: [TaskWorkspaceRecovery],
		model: inout WorkspaceCoordinatorModel
	)
	{
		model.workspaces = Dictionary(uniqueKeysWithValues: records.map
		{
			(
				$0.workspace.id,
				$0.workspace
			)
		})
		model.recoveryIssues = Dictionary(uniqueKeysWithValues: records.compactMap
		{
			item in
			item.kind == .active || item.kind == .checkoutRemoved || item
				.kind == .creationCancelled
				? nil : (item.workspace.id, item.kind)
		})
		model.recordsRevision += 1
	}

	private static func recoveryConflicts(
		_ records: [TaskWorkspaceRecovery],
		recoveredByID: [UUID: TaskWorkspace],
		model: WorkspaceCoordinatorModel
	) -> [(WorkspaceLifecycleOwnerReference, TaskWorkspace)]
	{
		var conflicts: [(WorkspaceLifecycleOwnerReference, TaskWorkspace)] = []
		for (owner, identity) in model.registeredOwners
		{
			guard case .managed(
				let id,
				_
			) = owner, let expected = model.workspaces[id],
							let recovered = recoveredByID[id]
			else
			{
				continue
			}
			let kind = records.first
			{
				$0.workspace.id == id
			}?.kind
			if !recovered.hasSameOwnership(as: expected) || recovered.threadID != expected
				.threadID
				||
				(recovered.phase != .active && recovered.phase != .removing && recovered
					.phase != .checkoutRemoved)
				|| kind == .ownershipConflict
			{
				conflicts.append((WorkspaceLifecycleOwnerReference(
					owner: owner,
					workspace: identity
				), expected))
			}
		}

		return conflicts
	}

	private static func reconcileRecoveredOwners(
		_ recoveredByID: [UUID: TaskWorkspace],
		model: inout WorkspaceCoordinatorModel
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		for (owner, identity) in model.registeredOwners
		{
			guard case .managed(
				let id,
				_
			) = owner, let expected = model.workspaces[id],
							let recovered = recoveredByID[id]
			else
			{
				continue
			}
			let reference = WorkspaceLifecycleOwnerReference(
				owner: owner,
				workspace: identity
			)
			effects.append(.managedRecordRecovered(
				reference,
				expected: expected,
				recovered: recovered
			))
			if let transition = model.pendingCleanup[id], transition.stage == .recovering,
				transition.request.expected == expected
			{
				model.pendingCleanup.removeValue(forKey: id)
				effects.append(.releaseCleanup(transition.request))
			}
			if recovered.phase == .checkoutRemoved, let observation = model.owners[owner],
				!observation.blocksCleanup, !observation.pendingLocalWrites
			{
				model.owners.removeValue(forKey: owner)
				model.registeredOwners.removeValue(forKey: owner)
				effects.append(.removeOwner(reference))
				if model.selectedOwner == owner
				{
					selectSource(&model)
				}
			}
		}
		for (id, transition) in model.pendingCleanup
			where transition.stage == .recovering && transition.request.owner == nil
		{
			if let recovered = recoveredByID[id],
				recovered.hasSameOwnership(as: transition.request.expected),
				recovered.threadID == transition.request.expected.threadID
			{
				model.pendingCleanup.removeValue(forKey: id)
			}
		}

		return effects
	}

}
