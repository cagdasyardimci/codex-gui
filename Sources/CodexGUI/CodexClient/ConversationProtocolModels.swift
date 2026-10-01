import Foundation

/// Values displayed by the app. The app-server remains the source of conversation history.
struct ThreadSummary: Equatable
{
	let id: String
	let name: String?
	let preview: String?
	let cwd: String
	let updatedAt: Date?
	let status: String

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.name = json["name"] as? String
		self.preview = json["preview"] as? String
		self.cwd = json["cwd"] as? String ?? ""
		if let seconds = json["updatedAt"] as? Double
		{
			self.updatedAt = Date(timeIntervalSince1970: seconds)
		}
		else
		{
			self.updatedAt = nil
		}
		self.status = (json["status"] as? [String: Any])?["type"] as? String ?? "notLoaded"
	}
}

struct ThreadDetail
{
	let summary: ThreadSummary
	let turns: [CodexTurn]
	let nextTurnsCursor: String?
}

struct CodexTurn
{
	let id: String
	let status: String
	let items: [CodexItem]
	let error: String?
	let startedAt: Date?
	let completedAt: Date?
	let durationMs: Double?

	init(
		id: String,
		status: String,
		items: [CodexItem],
		error: String?,
		startedAt: Date? = nil,
		completedAt: Date? = nil,
		durationMs: Double? = nil
	)
	{
		self.id = id
		self.status = status
		self.items = items
		self.error = error
		self.startedAt = startedAt
		self.completedAt = completedAt
		self.durationMs = durationMs
	}

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.status = json["status"] as? String ?? "inProgress"
		self.items = (json["items"] as? [[String: Any]] ?? []).compactMap(CodexItem.init(json:))
		self.error = (json["error"] as? [String: Any])?["message"] as? String
		self.startedAt = (json["startedAt"] as? NSNumber).map
		{
			Date(timeIntervalSince1970: $0.doubleValue)
		}
		self.completedAt = (json["completedAt"] as? NSNumber).map
		{
			Date(timeIntervalSince1970: $0.doubleValue)
		}
		self.durationMs = (json["durationMs"] as? NSNumber)?.doubleValue
	}
}

enum TurnPlanStepStatus: String, Equatable
{
	case pending
	case inProgress
	case completed
}

struct TurnPlanStep: Equatable
{
	let step: String
	let status: TurnPlanStepStatus

	init?(json: [String: Any])
	{
		guard let step = json["step"] as? String,
				let statusValue = json["status"] as? String,
				let status = TurnPlanStepStatus(rawValue: statusValue)
		else
		{
			return nil
		}
		self.step = step
		self.status = status
	}
}

struct TurnPlanUpdate: Equatable
{
	let threadId: String
	let turnId: String
	let explanation: String?
	let plan: [TurnPlanStep]

	init?(json: [String: Any])
	{
		guard let threadId = json["threadId"] as? String,
				let turnId = json["turnId"] as? String,
				let rawPlan = json["plan"] as? [[String: Any]]
		else
		{
			return nil
		}
		let plan = rawPlan.compactMap(TurnPlanStep.init(json:))
		guard plan.count == rawPlan.count
		else
		{
			return nil
		}
		self.threadId = threadId
		self.turnId = turnId
		self.explanation = json["explanation"] as? String
		self.plan = plan
	}
}

struct FileChange
{
	let path: String
	let kind: String
	let movePath: String?
	let diff: String

	init?(json: [String: Any])
	{
		guard let path = json["path"] as? String
		else
		{
			return nil
		}
		self.path = path
		self.kind =
			(json["kind"] as? [String: Any])?["type"] as? String
				?? json["kind"] as? String ?? "unknown"
		self.movePath = (json["kind"] as? [String: Any])?["move_path"] as? String
		self.diff = json["diff"] as? String ?? ""
	}
}

struct CodexItem
{
	let id: String
	let type: String
	let text: String?
	let command: String?
	let commandActions: [CodexCommandAction]
	let imagePath: String?
	let cwd: String?
	let output: String?
	let status: String?
	let exitCode: Int?
	let durationMs: Double?
	let changes: [FileChange]
	let references: [UserMessageReference]

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String, let type = json["type"] as? String
		else
		{
			return nil
		}
		self.id = id
		self.type = type
		if type == "userMessage"
		{
			let content = json["content"] as? [[String: Any]] ?? []
			self.references = content.enumerated().compactMap
			{
				index, value in
				UserMessageReference(
					json: value,
					id: "\(id):\(index)"
				)
			}
			self.text = content.compactMap
			{
				$0["text"] as? String
			}.joined(separator: "\n")
		}
		else
		{
			self.text = json["text"] as? String
			self.references = []
		}
		self.command = json["command"] as? String
		self.commandActions = (json["commandActions"] as? [[String: Any]] ?? [])
			.compactMap(CodexCommandAction.init(json:))
		self.imagePath = type == "imageView" ? json["path"] as? String : nil
		self.cwd = json["cwd"] as? String
		self.output = json["aggregatedOutput"] as? String
		self.status = json["status"] as? String
		self.exitCode = json["exitCode"] as? Int
		self.durationMs = (json["durationMs"] as? NSNumber)?.doubleValue
		self.changes = (json["changes"] as? [[String: Any]] ?? [])
			.compactMap(FileChange.init(json:))
	}
}

struct UserMessageReference: Equatable
{
	enum Kind: Equatable
	{
		case fileReference
		case image
	}

	let id: String
	let kind: Kind
	let name: String
	let path: String

	init?(json: [String: Any], id: String)
	{
		guard let type = json["type"] as? String,
				let path = json["path"] as? String
		else
		{
			return nil
		}
		switch type
		{
		case "mention":
			kind = .fileReference
		case "localImage":
			kind = .image
		default:
			return nil
		}
		self.id = id
		self.path = path
		self.name = json["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent
	}
}
