import Foundation

struct CodexSubagentActivity: Equatable, Sendable
{
	let kind: String
	let threadID: String?
	let path: String?
	/// Local lifecycle observations; the backend supplies no persisted activity timestamps.
	let completedAt: Date?
	let startedAt: Date?

	init(
		kind: String,
		threadID: String? = nil,
		path: String? = nil,
		completedAt: Date? = nil,
		startedAt: Date? = nil
	)
	{
		self.kind = kind
		self.threadID = threadID
		self.path = path
		self.completedAt = completedAt
		self.startedAt = startedAt
	}

	init(json: [String: Any])
	{
		kind = json["kind"] as? String ?? "unknown"
		threadID = json["agentThreadId"] as? String
		path = json["agentPath"] as? String
		completedAt = nil
		startedAt = nil
	}

	var isTerminal: Bool
	{
		kind == "completed" || kind == "failed" || kind == "interrupted"
	}

	func recordingLifecycle(
		at observedAt: Date?,
		previous: CodexSubagentActivity? = nil
	) -> CodexSubagentActivity
	{
		let retainedCompletion: Date?
		let sameAgent: Bool
		if threadID == nil, path == nil
		{
			sameAgent = previous != nil
		}
		else if let threadID, let previousThreadID = previous?.threadID
		{
			sameAgent = threadID == previousThreadID
		}
		else
		{
			sameAgent = path == previous?.path
		}
		if isTerminal, sameAgent, previous?.kind == kind
		{
			retainedCompletion = previous?.completedAt
		}
		else
		{
			retainedCompletion = nil
		}
		let resolvedStart: Date?
		if kind == "started"
		{
			let retainedStart = sameAgent && previous?.kind == "started" ? previous?.startedAt : nil
			resolvedStart = startedAt ?? retainedStart ?? observedAt
		}
		else
		{
			resolvedStart = startedAt ?? (sameAgent ? previous?.startedAt : nil)
		}
		return CodexSubagentActivity(
			kind: kind,
			threadID: threadID ?? (sameAgent ? previous?.threadID : nil),
			path: path ?? (sameAgent ? previous?.path : nil),
			completedAt: isTerminal ? completedAt ?? retainedCompletion ?? observedAt : nil,
			startedAt: resolvedStart
		)
	}

	var name: String
	{
		guard let components = nameComponents
		else
		{
			return "Subagent"
		}
		return components.map
		{
			$0.prefix(1).uppercased() + $0.dropFirst()
		}.joined(separator: " ")
	}

	/// The visible label follows the task's original casing after its initial capital.
	var displayName: String
	{
		guard let components = nameComponents
		else
		{
			return "Subagent"
		}
		let words = components.joined(separator: " ")
		return words.prefix(1).uppercased() + words.dropFirst()
	}

	private var nameComponents: [Substring]?
	{
		path?.split(separator: "/").last?.split(separator: "_")
	}

	/// A path can identify artwork, but only a backend thread ID can open a conversation.
	var conversationThreadID: String?
	{
		guard let threadID, !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			return nil
		}
		return threadID
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
