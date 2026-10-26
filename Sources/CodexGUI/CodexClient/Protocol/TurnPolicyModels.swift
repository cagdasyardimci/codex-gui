import Foundation

enum TurnApprovalPolicy: String, Codable
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
	case configuredWorkspaceWrite(networkAccess: Bool)
	case readOnly
	case dangerFullAccess

	var protocolValue: [String: Any]
	{
		switch self
		{
		case .workspaceWrite:
			["type": "workspaceWrite", "networkAccess": false]
		case .configuredWorkspaceWrite(let networkAccess):
			["type": "workspaceWrite", "networkAccess": networkAccess]
		case .readOnly:
			["type": "readOnly"]
		case .dangerFullAccess:
			["type": "dangerFullAccess"]
		}
	}
}
