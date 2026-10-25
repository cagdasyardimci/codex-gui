import Foundation

/// The controls and a new submission must describe the same next-turn settings.
struct ComposerSelection: Equatable
{
	let modelID: String?
	let effort: String?
	let fastMode: Bool
}

extension WorkspaceModel
{
	var composerSelection: ComposerSelection
	{
		let local = ComposerSelection(
			modelID: preferences.selectedModelID,
			effort: preferences.selectedEffort,
			fastMode: preferences.runPreferences.fastMode
		)
		guard case .thread(let id) = conversations.selectedConversation
		else
		{
			return local
		}
		if let override = preferences.localThreadSelections[id]
		{
			return override
		}
		guard let settings = composerCommands.threadSettings[id]
		else
		{
			return local
		}
		return ComposerSelection(
			modelID: settings.model,
			effort: settings.reasoningEffort,
			fastMode: FastModeAvailability.isFastTier(
				settings.serviceTier,
				modelID: settings.model,
				models: preferences.models
			)
		)
	}

	mutating func recordLocalComposerSelection(_ selection: ComposerSelection)
	{
		guard case .thread(let id) = conversations.selectedConversation
		else
		{
			return
		}
		preferences.localThreadSelections[id] = selection
	}

	mutating func reconcileRemoteComposerSelection(
		threadID: String,
		previous: ThreadSettings?,
		updated: ThreadSettings
	)
	{
		guard let local = preferences.localThreadSelections[threadID]
		else
		{
			return
		}
		guard let previous
		else
		{
			preferences.localThreadSelections[threadID] = nil
			return
		}
		let modelChanged = previous.model != updated.model
		let effortChanged = previous.reasoningEffort != updated.reasoningEffort
		let tierChanged = previous.serviceTier != updated.serviceTier
		preferences.localThreadSelections[threadID] = ComposerSelection(
			modelID: modelChanged ? updated.model : local.modelID,
			effort: modelChanged || effortChanged ? updated.reasoningEffort : local.effort,
			fastMode: modelChanged || tierChanged
				? FastModeAvailability.isFastTier(
					updated.serviceTier,
					modelID: updated.model,
					models: preferences.models
				) : local.fastMode
		)
	}
}
