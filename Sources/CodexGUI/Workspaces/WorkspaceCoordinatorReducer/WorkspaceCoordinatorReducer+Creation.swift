import Foundation

extension WorkspaceCoordinatorReducer
{
	static func reduceCreationAndSelection(
		_ model: inout WorkspaceCoordinatorModel,
		_ action: WorkspaceCoordinatorAction
	) -> [WorkspaceCoordinatorEffect]
	{
		var effects: [WorkspaceCoordinatorEffect] = []
		switch action
		{
		case .creationRequested(let request):
			let hasName = !request.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			guard model.acceptsNewWork, request.source == model.source,
					request.selectionEpoch == model.selectionEpoch,
					model.pendingCreations[request.requestID] == nil
			else
			{
				return []
			}
			guard request.source.canonicalCheckoutPath != nil, hasName
			else
			{
				model.message = "Choose a source repository and enter a task name."
				return []
			}
			model.pendingCreations[request.requestID] = request
			model.message = "Creating a checkout for \(request.name)…"
			effects.append(.git(.create(request)))
		case .creationFinished(
			let request,
			let result
		):
			guard model.pendingCreations[request.requestID] == request
			else
			{
				return []
			}
			model.pendingCreations.removeValue(forKey: request.requestID)
			switch result
			{
			case .succeeded(let workspace):
				guard workspace.taskID == request.taskID,
						workspace.sourceProjectPath == request.source.canonicalCheckoutPath,
						workspace.phase == .active,
						(model.workspaces[workspace.id] == nil
						|| model.workspaces[workspace.id] == workspace)
				else
				{
					return []
				}
				model.workspaces[workspace.id] = workspace
				model.recordsRevision += 1
				// Durable creation remains recorded even after the user's selection changes.
				if model.source == request.source, model.selectionEpoch == request.selectionEpoch
				{
					let selection = WorkspaceSelectionRequest(
						requestID: request.requestID,
						ownerSessionID: request.ownerSessionID,
						selectionEpoch: model.selectionEpoch + 1,
						expected: workspace
					)
					effects += reduce(
						&model,
						.selectionRequested(selection)
					)
				}
			case .failed(let failure):
				if model.source == request.source, model.selectionEpoch == request.selectionEpoch
				{
					model.message = "Could not create task checkout: \(failure.message)"
				}
			}
		case .selectionRequested(let request):
			let sameOwnerSession = model.registeredOwners.keys.allSatisfy
			{
				if case .managed(
					let id,
					let session
				) = $0
				{
					return id != request.expected.id || session == request.ownerSessionID
				}
				return true
			}
			guard model.acceptsNewWork, request.selectionEpoch == model.selectionEpoch + 1,
					model.workspaces[request.expected.id] == request.expected,
					request.expected.phase == .active, sameOwnerSession
			else
			{
				return []
			}

			model.selectionEpoch = request.selectionEpoch
			model.pendingSelection = request
			effects.append(.git(.verifySelection(request)))
		case .selectionVerified(
			let request,
			let result
		):
			guard model.pendingSelection == request, model.selectionEpoch == request.selectionEpoch
			else
			{
				return []
			}
			model.pendingSelection = nil
			guard model.acceptsNewWork, model.workspaces[request.expected.id] == request.expected
			else
			{
				return []
			}
			switch result
			{
			case .succeeded(let workspace):
				guard workspace == request.expected
				else
				{
					return []
				}
				model.selectedOwner = .managed(
					workspaceID: workspace.id,
					sessionID: request.ownerSessionID
				)
				model.registeredOwners[model.selectedOwner] = WorkspaceIdentity(
					sessionID: request.ownerSessionID,
					canonicalCheckoutPath: workspace.checkoutPath
				)
				model.recoveryIssues.removeValue(forKey: workspace.id)
				model.message = workspace.sourceWasDirty
					? "This task starts from committed HEAD. "
					+ "Source checkout edits stay in place." : nil
				effects.append(.attachVerifiedOwner(
					request,
					workspace
				))
			case .failed(let failure):
				model.message = "Could not open task checkout: \(failure.message)"
			}
		default:
			return []
		}
		return effects
	}
}
