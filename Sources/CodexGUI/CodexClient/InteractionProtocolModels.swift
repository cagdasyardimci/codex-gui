import Foundation

enum InteractionKind
{
	case commandApproval
	case fileChangeApproval
	case permissionApproval
	case question
	case unsupported(String)
}

struct InteractionQuestion
{
	struct Option
	{
		let label: String
		let description: String
	}

	let id: String
	let header: String
	let question: String
	let options: [Option]
	let allowsOther: Bool
	let isSecret: Bool

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String, let question = json["question"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.header = json["header"] as? String ?? "Question"
		self.question = question
		self.options = (json["options"] as? [[String: Any]] ?? []).compactMap
		{
			option in
			guard let label = option["label"] as? String
			else
			{
				return nil
			}
			return Option(
				label: label,
				description: option["description"] as? String ?? ""
			)
		}
		self.allowsOther = json["isOther"] as? Bool ?? false
		self.isSecret = json["isSecret"] as? Bool ?? false
	}
}

struct PendingInteraction
{
	/// Type-tagged JSON-RPC request key used when responding to this callback.
	let id: String
	let threadId: String
	let turnId: String
	let itemId: String
	let approvalId: String?
	let kind: InteractionKind
	let reason: String?
	let command: String?
	let cwd: String?
	let grantRoot: String?
	let networkHost: String?
	let networkProtocol: String?
	let questions: [InteractionQuestion]
	let requestedPermissions: [String: Any]?
	let additionalPermissions: [String: Any]?
	let availableDecisions: [ApprovalDecision]?
}

enum ApprovalDecision: Equatable
{
	case accept
	case acceptForSession
	case decline
	case cancel
	case acceptWithExecpolicyAmendment([String])
	case applyNetworkPolicyAmendment(
		host: String,
		action: String
	)

	init?(json: Any)
	{
		if let value = json as? String
		{
			switch value
			{
			case "accept": self = .accept
			case "acceptForSession": self = .acceptForSession
			case "decline": self = .decline
			case "cancel": self = .cancel
			default: return nil
			}
			return
		}

		guard let object = json as? [String: Any]
		else
		{
			return nil
		}
		if let amendment = object["acceptWithExecpolicyAmendment"] as? [String: Any],
			let commands = amendment["execpolicy_amendment"] as? [String]
		{
			self = .acceptWithExecpolicyAmendment(commands)
		}
		else if let amendment = object["applyNetworkPolicyAmendment"] as? [String: Any],
				let policy = amendment["network_policy_amendment"] as? [String: String],
				let host = policy["host"], let action = policy["action"],
				action == "allow" || action == "deny"
		{
			self = .applyNetworkPolicyAmendment(
				host: host,
				action: action
			)
		}
		else
		{
			return nil
		}
	}

	var wireValue: Any
	{
		switch self
		{
		case .accept: "accept"
		case .acceptForSession: "acceptForSession"
		case .decline: "decline"
		case .cancel: "cancel"
		case .acceptWithExecpolicyAmendment(let commands):
			["acceptWithExecpolicyAmendment": ["execpolicy_amendment": commands]]
		case .applyNetworkPolicyAmendment(
			let host,
			let action
		):
			[
				"applyNetworkPolicyAmendment": [
					"network_policy_amendment": ["host": host, "action": action]
				]
			]
		}
	}
}

enum PermissionScope: String
{
	case turn
	case session
}

enum InteractionResponse
{
	case approval(ApprovalDecision)
	case answers([String: [String]])
	case permissions(
		granted: [String: Any],
		scope: PermissionScope
	)
}
