import Foundation

/// Only settings explicitly saved in the UI override the local composer presets.
struct RunConfigurationDefaults: Codable, Equatable
{
	var approvalPolicy: TurnApprovalPolicy?
	var sandboxMode: SandboxMode?
	var networkAccess: Bool?
	var serviceTier: String?

	enum SandboxMode: String, Codable
	{
		case readOnly = "read-only"
		case workspaceWrite = "workspace-write"
		case dangerFullAccess = "danger-full-access"
	}

	var hasPermissionOverrides: Bool
	{
		approvalPolicy != nil || sandboxMode != nil || networkAccess != nil
	}

	var isEmpty: Bool
	{
		approvalPolicy == nil && sandboxMode == nil && networkAccess == nil && serviceTier == nil
	}

	mutating func apply(_ update: RunConfigurationDefaultsUpdate)
	{
		if update.keys.contains(.approvalPolicy)
		{
			approvalPolicy = update.values.approvalPolicy
		}
		if update.keys.contains(.sandboxMode)
		{
			sandboxMode = update.values.sandboxMode
		}
		if update.keys.contains(.networkAccess)
		{
			networkAccess = update.values.networkAccess
		}
		if update.keys.contains(.serviceTier)
		{
			serviceTier = update.values.serviceTier
		}
	}
}

/// A partial confirmed save. Missing keys preserve existing composer choices.
/// A null value clears an override.
struct RunConfigurationDefaultsUpdate: Equatable
{
	enum Key: Hashable
	{
		case approvalPolicy, sandboxMode, networkAccess, serviceTier
	}

	let keys: Set<Key>
	let values: RunConfigurationDefaults

	init?(effectiveConfig: [String: Any], editedKeys: Set<String>)
	{
		let permissionKeys: Set<String> = [
			"approval_policy",
			"sandbox_mode",
			"sandbox_workspace_write.network_access",
		]
		var selectedKeys = Set<String>()
		if !editedKeys.isDisjoint(with: permissionKeys)
		{
			selectedKeys.formUnion(permissionKeys)
		}
		if editedKeys.contains("service_tier")
		{
			selectedKeys.insert("service_tier")
		}
		var values: [String: Any] = [:]
		for key in selectedKeys
		{
			var value: Any? = effectiveConfig
			for component in key.split(separator: ".")
			{
				value = (value as? [String: Any])?[String(component)]
			}
			values[key] = value ?? NSNull()
		}
		self.init(confirmedValues: values)
	}

	private init?(confirmedValues: [String: Any])
	{
		var permissionsValid = true
		var keys = Set<Key>()
		var values = RunConfigurationDefaults()
		if let raw = confirmedValues["approval_policy"]
		{
			if raw is NSNull
			{
				keys.insert(.approvalPolicy)
			}
			else if let text = raw as? String, let policy = TurnApprovalPolicy(rawValue: text)
			{
				keys.insert(.approvalPolicy)
				values.approvalPolicy = policy
			}
			else
			{
				permissionsValid = false
			}
		}
		if let raw = confirmedValues["sandbox_mode"]
		{
			if raw is NSNull
			{
				keys.insert(.sandboxMode)
			}
			else if let text = raw as? String,
					let mode = RunConfigurationDefaults.SandboxMode(rawValue: text)
			{
				keys.insert(.sandboxMode)
				values.sandboxMode = mode
			}
			else
			{
				permissionsValid = false
			}
		}
		if let raw = confirmedValues["sandbox_workspace_write.network_access"]
		{
			if raw is NSNull
			{
				keys.insert(.networkAccess)
			}
			else if let enabled = raw as? Bool
			{
				keys.insert(.networkAccess)
				values.networkAccess = enabled
			}
			else
			{
				permissionsValid = false
			}
		}
		if !permissionsValid
		{
			// A custom policy must never become a partial preset through a sibling setting edit.
			keys.subtract([.approvalPolicy, .sandboxMode, .networkAccess])
			values.approvalPolicy = nil
			values.sandboxMode = nil
			values.networkAccess = nil
		}
		if let raw = confirmedValues["service_tier"]
		{
			if raw is NSNull
			{
				keys.insert(.serviceTier)
			}
			else if let tier = raw as? String, !tier.isEmpty
			{
				keys.insert(.serviceTier)
				values.serviceTier = tier
			}
		}
		guard !keys.isEmpty
		else
		{
			return nil
		}
		self.keys = keys
		self.values = values
	}
}
