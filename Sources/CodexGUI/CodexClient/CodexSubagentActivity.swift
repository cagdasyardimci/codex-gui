import Foundation

struct CodexSubagentActivity: Equatable, Sendable
{
	let kind: String
	let threadID: String?
	let path: String?

	init(json: [String: Any])
	{
		kind = json["kind"] as? String ?? "unknown"
		threadID = json["agentThreadId"] as? String
		path = json["agentPath"] as? String
	}

	var name: String
	{
		guard let component = path?.split(separator: "/").last
		else
		{
			return "Subagent"
		}
		return component.split(separator: "_").map
		{
			$0.prefix(1).uppercased() + $0.dropFirst()
		}.joined(separator: " ")
	}

	var identity: String
	{
		threadID ?? path ?? "subagent"
	}

	var action: String
	{
		switch kind
		{
		case "started": "started working"
		case "completed": "finished"
		case "interacted": "received input"
		case "failed": "failed"
		case "interrupted": "was interrupted"
		default: kind == "unknown" ? "activity" : kind
		}
	}
}
