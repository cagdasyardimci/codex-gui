import Foundation

struct ModelOption: Equatable
{
	let id: String
	let displayName: String
	let supportedReasoningEfforts: [String]
	let defaultReasoningEffort: String
	let isDefault: Bool

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
	}
}
