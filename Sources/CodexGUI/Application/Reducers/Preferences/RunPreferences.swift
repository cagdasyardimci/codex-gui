import Foundation

enum ApprovalMode: String, CaseIterable, Codable, Equatable
{
	case askForApproval
	case approveForMe
	case fullAccess

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

/// Captured before submitting a turn. Changing the next-turn controls never changes a running turn.
struct RunPreferences: Codable, Equatable
{
	let approvalMode: ApprovalMode
	let fastMode: Bool

	// The initial selection is explicit and conservative instead of inheriting unseen backend
	// policy.
	static let standard = RunPreferences(
		approvalMode: .askForApproval,
		fastMode: false
	)

	var approvalPolicy: TurnApprovalPolicy
	{
		approvalMode == .fullAccess ? .never : .onRequest
	}

	var approvalsReviewer: TurnApprovalsReviewer
	{
		approvalMode == .approveForMe ? .autoReview : .user
	}

	var sandboxPolicy: TurnSandboxPolicy
	{
		approvalMode == .fullAccess ? .dangerFullAccess : .workspaceWrite
	}

	var serviceTierForTurn: String
	{
		fastMode ? "priority" : "default"
	}
}
