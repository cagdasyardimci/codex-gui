import Foundation

enum ReviewTarget: Equatable
{
	case uncommittedChanges
	case baseBranch(branch: String)
	case commit(
		sha: String,
		title: String?
	)
	case custom(instructions: String)

	var protocolValue: [String: Any]
	{
		switch self
		{
		case .uncommittedChanges:
			return ["type": "uncommittedChanges"]
		case .baseBranch(let branch):
			return ["type": "baseBranch", "branch": branch]
		case .commit(
			let sha,
			let title
		):
			var value: [String: Any] = ["type": "commit", "sha": sha]
			if let title
			{
				value["title"] = title
			}
			return value
		case .custom(let instructions):
			return ["type": "custom", "instructions": instructions]
		}
	}
}

enum ReviewDelivery: String
{
	case inline
	case detached
}

struct ReviewStartResult
{
	let reviewThreadId: String
	let turn: CodexTurn
}

enum CollaborationModeKind: String, Codable, Equatable
{
	case plan
	case `default`
}

/// Uses the server's built-in instructions for the selected mode.
struct CollaborationMode: Codable, Equatable
{
	let mode: CollaborationModeKind
	let model: String
	let reasoningEffort: String?

	var protocolValue: [String: Any]
	{
		[
			"mode": mode.rawValue,
			"settings": [
				"model": model,
				"reasoning_effort": reasoningEffort as Any? ?? NSNull(),
				"developer_instructions": NSNull(),
			],
		]
	}

	init(
		mode: CollaborationModeKind,
		model: String,
		reasoningEffort: String?
	)
	{
		self.mode = mode
		self.model = model
		self.reasoningEffort = reasoningEffort
	}

	init?(json: [String: Any])
	{
		guard let rawMode = json["mode"] as? String,
				let mode = CollaborationModeKind(rawValue: rawMode),
				let settings = json["settings"] as? [String: Any],
				let model = settings["model"] as? String
		else
		{
			return nil
		}
		self.init(
			mode: mode,
			model: model,
			reasoningEffort: settings["reasoning_effort"] as? String
		)
	}
}

struct CollaborationModePreset: Equatable
{
	let name: String
	let mode: CollaborationModeKind?
	let model: String?
	let reasoningEffort: String?

	init?(json: [String: Any])
	{
		guard let name = json["name"] as? String
		else
		{
			return nil
		}
		self.name = name
		self.mode = (json["mode"] as? String).flatMap(CollaborationModeKind.init(rawValue:))
		self.model = json["model"] as? String
		self.reasoningEffort = json["reasoning_effort"] as? String
	}
}

enum ServiceTierUpdate: Equatable
{
	case unchanged
	case clear
	case tier(String)
}

/// Omitted values preserve existing settings. Only serviceTier has explicit clear semantics.
struct ThreadSettingsUpdate
{
	var collaborationMode: CollaborationMode?
	var model: String?
	var effort: String?
	var serviceTier: ServiceTierUpdate = .unchanged

	var protocolValue: [String: Any]
	{
		var value: [String: Any] = [:]
		if let collaborationMode
		{
			value["collaborationMode"] = collaborationMode.protocolValue
		}
		if let model
		{
			value["model"] = model
		}
		if let effort
		{
			value["effort"] = effort
		}
		switch serviceTier
		{
		case .unchanged: break
		case .clear: value["serviceTier"] = NSNull()
		case .tier(let tier): value["serviceTier"] = tier
		}
		return value
	}
}

struct ThreadSettings: Equatable
{
	let model: String
	let modelProvider: String?
	let cwd: String
	let reasoningEffort: String?
	let serviceTier: String?
	let collaborationMode: CollaborationMode?
	let approvalPolicy: String?
	let approvalsReviewer: String?

	init?(json: [String: Any])
	{
		guard let model = json["model"] as? String, let cwd = json["cwd"] as? String
		else
		{
			return nil
		}
		self.model = model
		self.cwd = cwd
		self.modelProvider = json["modelProvider"] as? String
		self.reasoningEffort = json["effort"] as? String ?? json["reasoningEffort"] as? String
		self.serviceTier = json["serviceTier"] as? String
		self.collaborationMode = (json["collaborationMode"] as? [String: Any])
			.flatMap(CollaborationMode.init(json:))
		self.approvalPolicy = json["approvalPolicy"] as? String
		self.approvalsReviewer = json["approvalsReviewer"] as? String
	}
}

struct ThreadStatus: Equatable
{
	let type: String
	let activeFlags: [String]

	init?(json: [String: Any])
	{
		guard let type = json["type"] as? String
		else
		{
			return nil
		}
		if type == "active", json["activeFlags"] as? [String] == nil
		{
			return nil
		}
		self.type = type
		self.activeFlags = json["activeFlags"] as? [String] ?? []
	}
}
