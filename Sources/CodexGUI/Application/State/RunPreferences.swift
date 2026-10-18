import Foundation

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
}
