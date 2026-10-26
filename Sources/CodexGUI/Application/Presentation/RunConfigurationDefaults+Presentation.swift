import Foundation

extension RunConfigurationDefaults
{
	func permissionDescription(fallback: ApprovalMode) -> String
	{
		let preferences = RunPreferences(
			approvalMode: fallback,
			fastMode: false,
			configurationDefaults: self
		)
		let sandbox: String
		switch preferences.sandboxPolicy
		{
		case .readOnly: sandbox = "Read-only files; network disabled"
		case .dangerFullAccess: sandbox = "Unrestricted file and network access"
		case .workspaceWrite: sandbox = "Workspace files; network disabled"
		case .configuredWorkspaceWrite(let networkAccess):
			sandbox = networkAccess
				? "Workspace files; network enabled" : "Workspace files; network disabled"
		}
		let approval = preferences.approvalPolicy == .never
			? "Command approvals: never" : "Command approvals: on request"
		return "\(sandbox). \(approval)."
	}
}
