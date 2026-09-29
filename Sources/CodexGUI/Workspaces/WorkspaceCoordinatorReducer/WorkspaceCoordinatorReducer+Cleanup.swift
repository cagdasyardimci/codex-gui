import Foundation

extension WorkspaceCoordinatorReducer
{
	static func reduceCleanupAndCancellation(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		switch action
		{
		case .cleanupRequested(let request):
			guard model.acceptsNewWork,
					model.recoveryIssues[request.expected.id] != .ownershipConflict,
					model.workspaces[request.expected.id] == request.expected,
					request.expected.phase == .active || request.expected.phase == .removing,
					model.pendingCleanup[request.expected.id] == nil,
					cleanupEligible(
					request,
					model: model,
					requiresLease: false
					)
			else
			{
				return []
			}
			model.pendingCleanup[request.expected.id] = WorkspaceCleanupTransition(
				request: request,
				stage: request.owner == nil ? .draining : .reserving
			)
			effects.append(request.owner == nil ? .drainCleanup(request) : .reserveCleanup(request))
		case .cleanupReserved(
			let request,
			let accepted
		):
			guard model.pendingCleanup[request.expected.id]?.request == request,
					model.pendingCleanup[request.expected.id]?.stage == .reserving
			else
			{
				return []
			}
			if accepted, cleanupEligible(
				request,
				model: model,
				requiresLease: true
			)
			{
				model.pendingCleanup[request.expected.id]?.stage = .draining
				effects.append(.drainCleanup(request))
			}
			else
			{
				model.pendingCleanup.removeValue(forKey: request.expected.id)
				effects.append(.releaseCleanup(request))
			}
		case .cleanupPersistenceDrained(
			let request,
			let result
		):
			guard model.pendingCleanup[request.expected.id]?.request == request,
					model.pendingCleanup[request.expected.id]?.stage == .draining
			else
			{
				return []
			}
			if case .succeeded = result, cleanupEligible(
				request,
				model: model,
				requiresLease: true
			)
			{
				model.pendingCleanup[request.expected.id]?.stage = .removing
				effects.append(.git(.remove(request)))
			}
			else
			{
				model.pendingCleanup.removeValue(forKey: request.expected.id)
				effects.append(.releaseCleanup(request))
				if case .failed(let failure) = result
				{
					model.message = "Could not remove task checkout: \(failure.message)"
				}
			}
		case .cleanupFinished(
			let request,
			let result
		):
			guard model.pendingCleanup[request.expected.id]?.request == request,
					model.pendingCleanup[request.expected.id]?.stage == .removing
			else
			{
				return []
			}
			model.pendingCleanup.removeValue(forKey: request.expected.id)
			effects.append(.releaseCleanup(request))
			switch result
			{
			case .succeeded(let removed):
				guard removed.hasSameOwnership(as: request.expected),
						removed.threadID == request.expected.threadID,
						removed.phase == .checkoutRemoved
				else
				{
					return effects
				}
				model.workspaces[removed.id] = removed
				model.recordsRevision += 1
				if let owner = request.owner
				{
					model.owners.removeValue(forKey: owner.owner)
					model.registeredOwners.removeValue(forKey: owner.owner)
					effects.append(.removeOwner(owner))
					if model.selectedOwner == owner.owner
					{
						selectSource(&model)
					}
				}
				model.message = "Task checkout removed. "
					+ "Its branch and conversation remain available."
			case .failed(let failure):
				effects.removeAll
				{
					if case .releaseCleanup = $0
					{
						return true
					}
					return false
				}
				model.pendingCleanup[request.expected.id] = WorkspaceCleanupTransition(
					request: request,
					stage: .recovering
				)
				model.message = "Could not remove task checkout: \(failure.message)"
				let recovery = WorkspaceRecoveryRequest(
					requestID: request.requestID,
					recordsRevision: model.recordsRevision,
					cleanup: request
				)
				effects += reduce(
					&model,
					.recoveryRequested(recovery)
				)
			}
		case .cancellationRequested(
			let id,
			let expected
		):
			guard model.acceptsNewWork, model.workspaces[expected.id] == expected,
					expected.phase == .preparing,
					model.pendingCancellation[id] == nil
			else
			{
				return []
			}
			model.pendingCancellation[id] = expected
			effects.append(.git(.cancelCreation(
				requestID: id,
				expected: expected
			)))
		case .cancellationFinished(
			let id,
			let expected,
			let result
		):
			guard model.pendingCancellation[id] == expected
			else
			{
				return []
			}
			model.pendingCancellation.removeValue(forKey: id)
			switch result
			{
			case .succeeded(let cancelled):
				guard cancelled.hasSameOwnership(as: expected),
						cancelled.phase == .creationCancelled
				else
				{
					return []
				}
				model.workspaces[cancelled.id] = cancelled
				model.recordsRevision += 1
				model.recoveryIssues.removeValue(forKey: cancelled.id)
				model.message = "Incomplete task creation canceled."
			case .failed(let failure):
				model.message = "Could not cancel task creation: \(failure.message)"
			}
		default:
			return []
		}
		return effects
	}

	static func cleanupEligible(
		_ request: WorkspaceCleanupRequest,
		model: WorkspaceCoordinatorModel,
		requiresLease: Bool
	) -> Bool
	{
		guard model.workspaces[request.expected.id] == request.expected
		else
		{
			return false
		}
		guard let owner = request.owner
		else
		{
			let hasRegisteredOwner = model.registeredOwners.keys.contains
			{
				if case .managed(
					let id,
					_
				) = $0
				{
					return id == request.expected.id
				}
				return false
			}
			return request.expected.threadID == nil && !hasRegisteredOwner
		}
		guard case .managed(
			let id,
			_
		) = owner.owner, id == request.expected.id,
			valid(
				owner,
				model: model
			), let observation = model.owners[owner.owner],
			observation.reference == owner, !observation.blocksCleanup
		else
		{
			return false
		}
		return requiresLease ? observation.cleanupReservation == request.requestID
			: observation.cleanupReservation == nil
	}

}
