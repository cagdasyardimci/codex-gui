import Foundation

struct PreferenceWrite
{
	let context: OperationContext
	let value: Value

	enum Key: Hashable
	{
		case model, run, recent
		case pin(String)
		case taskPin(String)
		case name(String)
	}

	var key: Key
	{
		switch value
		{
		case .model: .model
		case .run: .run
		case .recent: .recent
		case .taskPin(
			let task,
			_
		): .taskPin(task.id)
		case .pin(
			let path,
			_
		): .pin(path)
		case .name(
			let path,
			_
		): .name(path)
		}
	}

	enum Value
	{
		case model(ProjectModelPreference)
		case run(RunPreferences)
		case pin(
			path: String,
			pinned: Bool
		)
		case taskPin(
			ThreadSummary,
			pinned: Bool
		)
		case name(
			path: String,
			name: String
		)
		case recent(path: String)
	}
}

/// Account and catalog reads belong to the transport, including its initial source binding.
enum PreferenceScope
{
	static func accepts(
		_ context: OperationContext,
		model: WorkspaceModel
	) -> Bool
	{
		context.workspace.sessionID == model.identity.sessionID
			&& context.generation == model.connection.generation
	}
}

extension PreferencesModel
{
	mutating func resolveSelection()
	{
		let preference = projectModelPreference ?? globalModelPreference
		hasStoredModelPreference = preference != nil
		selectedModelID = preference.map(\.modelID) ?? models.first(where: \.isDefault)?.id
		selectedEffort = preference?.effort
	}

	func warning(skillWarning: String?) -> String?
	{
		if let modelListError
		{
			return "\(modelListError) Reconnect before sending."
		}
		if let skillWarning
		{
			return skillWarning
		}
		if let selectedModelID, !models.contains(where:
			{
				$0.id == selectedModelID
			})
		{
			return "Saved model \(selectedModelID) is unavailable. Choose a model before sending."
		}
		if let selectedEffort
		{
			let selected = selectedModelID.flatMap
			{
				id in models.first
				{
					$0.id == id
				}
			}
			?? models.first(where: \.isDefault)
			if selected?.supportedReasoningEfforts.contains(selectedEffort) != true
			{
				return "Saved reasoning effort \(selectedEffort) is unavailable. Choose an effort "
					+ "before sending."
			}
		}
		return nil
	}
}
