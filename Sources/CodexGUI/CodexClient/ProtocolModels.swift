import CoreFoundation
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

/// JSON-RPC request IDs retain their wire type so integer 13 and string "13" stay distinct.
enum JSONRPCRequestID: Hashable
{
	case integer(Int64)
	case string(String)

	init?(json: Any)
	{
		if let value = json as? String
		{
			self = .string(value)
			return
		}
		guard let number = json as? NSNumber,
				CFGetTypeID(number) != CFBooleanGetTypeID(),
				!["d", "f"].contains(String(cString: number.objCType)),
				let value = Int64(number.stringValue)
		else
		{
			return nil
		}
		self = .integer(value)
	}

	var key: String
	{
		switch self
		{
		case .integer(let value): "integer:\(value)"
		case .string(let value): "string:\(value)"
		}
	}

	var wireValue: Any
	{
		switch self
		{
		case .integer(let value): value
		case .string(let value): value
		}
	}
}

enum AppServerEvent
{
	case turnStarted(
		threadId: String,
		turn: CodexTurn
	)
	case turnCompleted(
		threadId: String,
		turn: CodexTurn
	)
	case itemStarted(
		threadId: String,
		turnId: String,
		item: CodexItem
	)
	case itemCompleted(
		threadId: String,
		turnId: String,
		item: CodexItem
	)
	case agentMessageDelta(
		threadId: String,
		turnId: String,
		itemId: String,
		text: String
	)
	case commandOutputDelta(
		threadId: String,
		turnId: String,
		itemId: String,
		text: String
	)
	case fileChangeUpdated(
		threadId: String,
		turnId: String,
		itemId: String,
		changes: [FileChange]
	)
	case diffUpdated(
		threadId: String,
		turnId: String,
		diff: String
	)
	case planUpdated(TurnPlanUpdate)
	case toolProgress(
		threadId: String,
		turnId: String,
		itemId: String,
		message: String
	)
	case interaction(PendingInteraction)
	case interactionResolved(
		threadId: String,
		requestID: String
	)
	case accountUpdated
	case skillsChanged
	case rateLimitsUpdated
	case error(
		threadId: String,
		turnId: String,
		message: String,
		willRetry: Bool
	)
}
