import Foundation

enum TurnApprovalPolicy: String
{
	case onRequest = "on-request"
	case never
}

enum TurnApprovalsReviewer: String
{
	case user
	case autoReview = "auto_review"
}

enum TurnSandboxPolicy
{
	case workspaceWrite
	case dangerFullAccess

	var protocolValue: [String: Any]
	{
		switch self
		{
		case .workspaceWrite:
			["type": "workspaceWrite", "networkAccess": false]
		case .dangerFullAccess:
			["type": "dangerFullAccess"]
		}
	}
}
