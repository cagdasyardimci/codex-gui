import Foundation

extension WorkspaceLifecycleReducer
{
	static func reference(_ model: WorkspaceModel) -> WorkspaceLifecycleOwnerReference
	{
		WorkspaceLifecycleOwnerReference(
			owner: model.lifecycle.owner ?? .source(sessionID: model.identity.sessionID),
			workspace: model.identity
		)
	}

	static func hasUnresolvedComposer(_ model: WorkspaceModel) -> Bool
	{
		model.lifecycle.pendingInputPreparation != nil
			|| !model.composer.uncertainSubmissions.isEmpty
			|| model.composer.pendingSubmissions.keys.contains
			{
				!model.composer.acknowledgedSubmissions.contains($0)
			}
	}

	static func blocksCleanup(_ model: WorkspaceModel) -> Bool
	{
		model.lifecycle.managedOwnershipConflict != nil || model.blocksExecutionCleanup
			|| hasUnresolvedComposer(model)
			|| model.conversations.pendingManagement != nil
			|| model.conversations.pendingProjectArchive != nil
			|| model.composerCommands.blocksNewWork
	}

	static func accepts(
		_ action: WorkspaceAction,
		model: WorkspaceModel
	) -> Bool
	{
		if model.lifecycle.isShutdown
		{
			return false
		}
		if case .workspaceLifecycle(.sourceStartupRequested(let context)) = action
		{
			guard case .source(let sessionID) = reference(model).owner,
					sessionID == model.identity.sessionID,
					model.identity.canonicalCheckoutPath == nil,
					valid(
					context,
					model
					), !blocksCleanup(model)
			else
			{
				return false
			}
		}
		if model.lifecycle.managedOwnershipConflict != nil
		{
			switch action
			{
			case .connection(.connectRequested), .execution(.submissionRequested),
					.execution(.steeringRequested), .execution(.reconciliationRequested),
					.conversations(.managementRequested),
					.workspaceLifecycle(.inputPreparationRequested),
					.workspaceLifecycle(.bootstrapRequested),
					.workspaceLifecycle(.cleanupReserved): return false
			default: break
			}
		}
		if case .workspaceLifecycle(.projectOpeningRequested) = action
		{
			if case .managed = reference(model).owner
			{
				return false
			}
			if blocksCleanup(model)
			{
				return false
			}
		}
		if case .connection(.projectOpened(
			let identity,
			_
		)) = action
		{
			if case .managed = reference(model).owner
			{
				return false
			}
			if identity.sessionID != model.identity
				.sessionID || blocksCleanup(model)
			{
				return false
			}
		}
		let inactiveManagedWorkspace = model.lifecycle.managedWorkspace
			.map
			{
				$0.phase != .active
			} ?? false
		let inputsFrozen = model.lifecycle.cleanupReservation != nil
			|| model.lifecycle.quitReservation != nil
		if inactiveManagedWorkspace && !inputsFrozen
		{
			// Missing remote authority does not freeze independent local draft ownership.
			switch action
			{
			case .composer(.draftEdited), .composer(.contextAttached), .composer(.contextRemoved),
					.composer(.referenceReused), .contextNavigation(.contextEdited),
					.contextNavigation(.savedPromptInserted), .contextNavigation(.bookmarkToggled),
					.preferences(.modelSelected), .preferences(.effortSelected),
					.preferences(.approvalModeSelected), .preferences(.fastModeSelected),
					.preferences(.configurationDefaultsApplied),
					.preferences(.projectPinToggled), .preferences(.projectRenamed),
					.workspaceLifecycle(.projectPinRequested),
					.workspaceLifecycle(.projectRenameRequested),
					.conversations(.newChatRequested), .conversations(.newChatOpened): return true
			default: break
			}
		}
		guard inputsFrozen || inactiveManagedWorkspace
		else
		{
			return true
		}
		switch action
		{
		case .composerCommand(.requested), .composerCommand(.acknowledged),
				.composerCommand(.settingsRetryRequested): return false
		case .connection(.connectRequested), .connection(.projectOpened): return false
		case .execution(.submissionRequested), .execution(.steeringRequested): return false
		case .composer(.draftEdited), .composer(.contextAttached), .composer(.contextRemoved),
				.composer(.referenceReused): return false
		case .conversations(.newChatRequested), .conversations(.newChatOpened),
				.conversations(.selectionRequested),
				.conversations(.lockedChatRetryRequested),
				.conversations(.archivedFilterRequested),
				.conversations(.managementRequested): return false
		case .review(.turnSelected), .review(.markerRequested), .review(.changeRequestPrepared):
			return false
		case .contextNavigation(.contextEdited), .contextNavigation(.savedPromptInserted),
				.contextNavigation(.bookmarkToggled), .contextNavigation(.searchRequested),
				.contextNavigation(.moreSearchHistoryRequested), .contextNavigation(.jumpRequested):
			return false
		case .preferences(.modelSelected), .preferences(.effortSelected),
				.preferences(.approvalModeSelected), .preferences(.fastModeSelected),
				.preferences(.configurationDefaultsApplied),
				.preferences(.projectPinToggled), .preferences(.projectRenamed),
				.preferences(.projectRemembered), .preferences(.signInRequested),
				.preferences(.signOutRequested): return false
		case .workspaceLifecycle(.projectPinRequested),
				.workspaceLifecycle(.projectRenameRequested),
				.workspaceLifecycle(.projectOpeningRequested),
				.workspaceLifecycle(.archivedSelectionRequested),
				.workspaceLifecycle(.inputPreparationRequested),
				.workspaceLifecycle(.sourceStartupRequested),
				.workspaceLifecycle(.bootstrapRequested), .workspaceLifecycle(.refreshRequested),
				.workspaceLifecycle(.composerHydrationRequested): return false
		default: return true
		}
	}
}
