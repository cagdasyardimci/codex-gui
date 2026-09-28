import Foundation

struct SkillReference: Equatable
{
	let name: String
	let path: String
}

struct AvailableSkill: Equatable
{
	let name: String
	let description: String
	let path: String
	let scope: String
	let enabled: Bool
	let displayName: String?
	let shortDescription: String?
	let defaultPrompt: String?

	init?(json: [String: Any])
	{
		guard let name = json["name"] as? String,
				let description = json["description"] as? String,
				let path = json["path"] as? String,
				let scope = json["scope"] as? String,
				let enabled = json["enabled"] as? Bool
		else
		{
			return nil
		}
		let interface = json["interface"] as? [String: Any]
		self.name = name
		self.description = description
		self.path = path
		self.scope = scope
		self.enabled = enabled
		self.displayName = interface?["displayName"] as? String
		self.shortDescription =
			interface?["shortDescription"] as? String
				?? json["shortDescription"] as? String
		self.defaultPrompt = interface?["defaultPrompt"] as? String
	}
}

struct SkillDiscoveryError: Equatable
{
	let path: String
	let message: String

	init?(json: [String: Any])
	{
		guard let path = json["path"] as? String,
				let message = json["message"] as? String
		else
		{
			return nil
		}
		self.path = path
		self.message = message
	}
}

struct SkillCatalog: Equatable
{
	let skills: [AvailableSkill]
	let errors: [SkillDiscoveryError]
}
