import Foundation

/// Projects loaded lifecycle activity once for the transcript, summary and Subagents panel.
struct ConversationSubagents: Equatable
{
	enum Status: Equatable
	{
		case active, completed, failed, interrupted

		var label: String
		{
			switch self
			{
			case .active: "Active"
			case .completed: "Done"
			case .failed: "Failed"
			case .interrupted: "Interrupted"
			}
		}
	}

	private struct Record: Equatable
	{
		var activity: CodexSubagentActivity
		var status: Status
	}

	private enum Identity: Hashable
	{
		case thread(String), path(String), anonymous

		init(_ activity: CodexSubagentActivity)
		{
			if let threadID = activity.threadID
			{
				self = .thread(threadID)
			}
			else if let path = activity.path
			{
				self = .path(path)
			}
			else
			{
				self = .anonymous
			}
		}
	}

	private var records: [Record] = []

	init(entries: [ConversationEntry])
	{
		var identityIndices: [Identity: Int] = [:]
		var pathIndices: [String: Int] = [:]
		for entry in entries
		{
			guard case .subagent(let activity) = entry.activity
			else
			{
				continue
			}
			let pathIndex = activity.path.flatMap
			{
				pathIndices[$0]
			}
			let matchingPathIndex = pathIndex.flatMap
			{
				index in
				let recordedThreadID = records[index].activity.threadID
				let sameThread = activity.threadID == nil || recordedThreadID == nil
					|| activity.threadID == recordedThreadID
				return sameThread ? index : nil
			}
			let existingIndex = identityIndices[Identity(activity)] ?? matchingPathIndex
			if let index = existingIndex
			{
				let previous = records[index]
				let descriptiveActivity = Self.retainIdentity(
					activity,
					previous: previous
				)
				records[index] = Record(
					activity: descriptiveActivity,
					status: Self.status(activity.kind) ?? previous.status
				)
				identityIndices[Identity(descriptiveActivity)] = index
				if let path = descriptiveActivity.path
				{
					pathIndices[path] = index
				}
			}
			else
			{
				identityIndices[Identity(activity)] = records.count
				if let path = activity.path
				{
					pathIndices[path] = records.count
				}
				records.append(Record(
					activity: activity.recordingLifecycle(at: nil),
					status: Self.status(activity.kind) ?? .active
				))
			}
		}
	}

	var agents: [CodexSubagentActivity]
	{
		records.map(\.activity)
	}

	var activeAgents: [CodexSubagentActivity]
	{
		records.filter
		{
			$0.status == .active
		}.map(\.activity)
	}

	var doneAgents: [CodexSubagentActivity]
	{
		records.filter
		{
			$0.status != .active
		}.map(\.activity)
	}

	func status(for agent: CodexSubagentActivity) -> Status?
	{
		records.first
		{
			$0.activity.identity == agent.identity
		}?.status
	}

	func summary(parentThreadID: String) -> SummaryAgentProjection
	{
		SummaryAgentProjection(
			identities: agents.map
			{
				DelegatedAgentIdentity(
					parentThreadID: parentThreadID,
					agentThreadID: $0.identity
				)
			},
			completedCount: doneAgents.count,
			runningCount: activeAgents.count,
			aggregationDescription: "Subagents in loaded conversation history"
		)
	}

	func completedAt(for agent: CodexSubagentActivity) -> Date?
	{
		records.first
		{
			$0.activity.identity == agent.identity && $0.status != .active
		}?.activity.completedAt
	}

	func startedAt(for agent: CodexSubagentActivity) -> Date?
	{
		records.first
		{
			$0.activity.identity == agent.identity
		}?.activity.startedAt
	}

	private static func status(_ kind: String) -> Status?
	{
		switch kind
		{
		case "started": .active
		case "completed": .completed
		case "failed": .failed
		case "interrupted": .interrupted
		// Input and unfamiliar events are observations, not lifecycle transitions.
		default: nil
		}
	}

	private static func retainIdentity(
		_ activity: CodexSubagentActivity,
		previous: Record
	) -> CodexSubagentActivity
	{
		// Sparse lifecycle events retain the agent name and established thread identity.
		let incomingStatus = status(activity.kind)
		let completedAt: Date?
		if incomingStatus == .active
		{
			completedAt = nil
		}
		else if let incomingStatus
		{
			completedAt = activity.completedAt
				?? (incomingStatus == previous.status ? previous.activity.completedAt : nil)
		}
		else
		{
			completedAt = previous.activity.completedAt
		}
		return CodexSubagentActivity(
			kind: activity.kind,
			threadID: activity.threadID ?? previous.activity.threadID,
			path: activity.path ?? previous.activity.path,
			completedAt: completedAt,
			startedAt: incomingStatus == .active
				? activity.startedAt : activity.startedAt ?? previous.activity.startedAt
		)
	}
}
