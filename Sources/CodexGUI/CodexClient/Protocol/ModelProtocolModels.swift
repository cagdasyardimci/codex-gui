import Foundation

struct ModelOption: Equatable
{
	let id: String
	let displayName: String
	let supportedReasoningEfforts: [String]
	let defaultReasoningEffort: String
	let isDefault: Bool
	let serviceTiers: [ModelServiceTier]
	let defaultServiceTier: String?
	let supportsPersonality: Bool

	init?(json: [String: Any])
	{
		guard let id = json["model"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.displayName = json["displayName"] as? String ?? id
		self.supportedReasoningEfforts =
			(json["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
				.compactMap
				{
					$0["reasoningEffort"] as? String
				}
		self.defaultReasoningEffort = json["defaultReasoningEffort"] as? String ?? "medium"
		self.isDefault = json["isDefault"] as? Bool ?? false
		self.serviceTiers = (json["serviceTiers"] as? [[String: Any]] ?? [])
			.compactMap(ModelServiceTier.init(json:))
		self.defaultServiceTier = json["defaultServiceTier"] as? String
		self.supportsPersonality = json["supportsPersonality"] as? Bool ?? false
	}
}

struct ModelServiceTier: Equatable
{
	let id: String
	let name: String
	let description: String

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String,
				let name = json["name"] as? String,
				let description = json["description"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.name = name
		self.description = description
	}
}
