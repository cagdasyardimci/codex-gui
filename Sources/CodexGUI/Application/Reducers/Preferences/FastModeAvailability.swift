import Foundation

/// Fast mode is available only when the selected model advertises a matching service tier.
enum FastModeAvailability
{
	static func isFastTier(
		_ tier: String?,
		modelID: String,
		models: [ModelOption]
	) -> Bool
	{
		guard let tier
		else
		{
			return false
		}
		if tier == "priority" || tier == "fast"
		{
			return true
		}
		return models.first(where:
			{
				$0.id == modelID
			})?.serviceTiers.contains(where:
			{
				$0.id == tier && $0.name.caseInsensitiveCompare("fast") == .orderedSame
			}) == true
	}

	static func serviceTier(in model: WorkspaceModel) -> String?
	{
		guard let selected = selectedModel(in: model)
		else
		{
			return nil
		}
		return selected.serviceTiers.first(where:
			{
				$0.id == "priority"
			})?.id
			?? selected.serviceTiers.first(where:
				{
					$0.id.caseInsensitiveCompare("fast") == .orderedSame
						|| $0.name.caseInsensitiveCompare("fast") == .orderedSame
				})?.id
	}

	static func unavailableReason(in model: WorkspaceModel) -> String?
	{
		guard selectedModel(in: model) != nil
		else
		{
			return "Model catalog is unavailable. Reconnect before enabling fast mode."
		}
		return serviceTier(in: model) == nil ? "Fast mode is unavailable for the selected model." :
			nil
	}

	private static func selectedModel(in model: WorkspaceModel) -> ModelOption?
	{
		if let id = model.composerSelection.modelID
		{
			return model.preferences.models.first
			{
				$0.id == id
			}
		}
		return model.preferences.models.first(where: \.isDefault)
	}
}
