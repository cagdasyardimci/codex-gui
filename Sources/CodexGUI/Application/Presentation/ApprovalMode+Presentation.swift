import Foundation

extension ApprovalMode
{
	var title: String
	{
		switch self
		{
		case .askForApproval: "Ask for approval"
		case .approveForMe: "Approve for me"
		case .fullAccess: "Full access"
		}
	}

	var description: String
	{
		switch self
		{
		case .askForApproval:
			"Work in the project sandbox and ask you for additional file or network access."
		case .approveForMe:
			"Work in the project sandbox and let Codex's risk reviewer approve or deny access "
				+ "requests."
		case .fullAccess:
			"Allow unrestricted file and network access without command approvals."
		}
	}
}
