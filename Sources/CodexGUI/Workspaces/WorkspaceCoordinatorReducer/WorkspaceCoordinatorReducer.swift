import Foundation

/// Workspace lifecycle authority comes from captured identities and canonical owner observations.
enum WorkspaceCoordinatorReducer
{
	static func reduce(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		switch action
		{
		case .sourceOpened(let source):
			guard model.acceptsNewWork, source.sessionID == model.source.sessionID,
					model.owners[.source(sessionID: source.sessionID)]?.blocksCleanup != true
			else
			{
				return []
			}
			model.source = source
			model.registeredOwners[.source(sessionID: source.sessionID)] = source
			model.owners.removeValue(forKey: .source(sessionID: source.sessionID))
			selectSource(&model)
		case .sourceSelected:
			selectSource(&model)
		case .ownerObserved(let observation):
			guard valid(
				observation.reference,
				model: model
			)
			else
			{
				return []
			}
			let previous = model.owners.updateValue(
				observation,
				forKey: observation.reference.owner
			)
			effects.append(.ownerTransition(
				previous: previous,
				current: observation
			))
			for (id, transition) in model.pendingCleanup
				where transition.request.owner == observation.reference
			{
				if observation.blocksCleanup
					|| (transition.stage != .reserving
						&& observation.cleanupReservation != transition.request.requestID)
				{
					model.pendingCleanup.removeValue(forKey: id)
					effects += [.cancelRequest(transition.request.requestID),
								.releaseCleanup(transition.request)]
					model.message = "Stop this task and wait for its outcome "
						+ "before removing its checkout."
				}
			}
			advanceQuit(
				&model,
				effects: &effects
			)
		case .ownerRemoved(let reference):
			guard case .managed = reference.owner,
					model.owners[reference.owner]?.reference == reference,
					model.owners[reference.owner]?.blocksCleanup == false,
					model.owners[reference.owner]?.cleanupReservation == nil,
					model.owners[reference.owner]?.pendingLocalWrites == false
			else
			{
				return []
			}
			model.owners.removeValue(forKey: reference.owner)
			model.registeredOwners.removeValue(forKey: reference.owner)
			if model.selectedOwner == reference.owner
			{
				selectSource(&model)
			}
			advanceQuit(
				&model,
				effects: &effects
			)
		case .bindingObserved(
			let reference,
			let workspace
		):
			guard valid(
				reference,
				model: model
			),
				model.owners[reference.owner]?.reference == reference,
				case .managed(
					let id,
					_
				) = reference.owner,
				id == workspace.id, let previous = model.workspaces[id],
				previous.hasSameOwnership(as: workspace), previous.phase == workspace.phase,
				previous.threadID == nil || previous.threadID == workspace.threadID,
				previous != workspace
			else
			{
				return []
			}
			model.workspaces[id] = workspace
			model.recordsRevision += 1
			if let cleanup = model.pendingCleanup.removeValue(forKey: id)
			{
				effects += [
					.cancelRequest(cleanup.request.requestID),
					.releaseCleanup(cleanup.request)
				]
			}
		case .creationRequested, .creationFinished, .selectionRequested, .selectionVerified:
			effects += reduceCreationAndSelection(
				&model,
				action
			)
		case .recoveryRequested, .recoveryFinished:
			effects += reduceRecovery(
				&model,
				action
			)
		case .cleanupRequested,
				.cleanupReserved,
				.cleanupPersistenceDrained,
				.cleanupFinished,
				.cancellationRequested,
				.cancellationFinished:
			effects += reduceCleanupAndCancellation(
				&model,
				action
			)
		case .quitRequested,
				.quitConfirmationFinished,
				.quitReservationFailed,
				.quitPersistenceDrained,
				.quitCompletionRequested:
			effects += reduceQuit(
				&model,
				action
			)
		}
		for effect in effects
		{
			if case .completeQuit(
				let request,
				let approved
			) = effect
			{
				model.pendingQuitCompletion = WorkspaceQuitCompletion(
					request: request,
					approved: approved,
					owners: Set(model.owners.values.map(\.reference))
				)
			}
		}
		return effects
	}

	static func selectSource(_ model: inout WorkspaceCoordinatorModel)
	{
		model.selectionEpoch += 1
		model.pendingSelection = nil
		model.selectedOwner = .source(sessionID: model.source.sessionID)
		model.message = nil
	}

	static func valid(
		_ reference: WorkspaceLifecycleOwnerReference,
		model: WorkspaceCoordinatorModel
	) -> Bool
	{
		guard reference.owner.sessionID == reference.workspace.sessionID,
				model.registeredOwners[reference.owner] == reference.workspace
		else
		{
			return false
		}
		switch reference.owner
		{
		case .source:
			return reference.workspace == model.source
		case .managed(
			let id,
			_
		):
			return model.workspaces[id]?.checkoutPath == reference.workspace.canonicalCheckoutPath
		}
	}

}
