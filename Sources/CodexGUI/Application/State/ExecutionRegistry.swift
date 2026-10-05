import Foundation

/// Draft lifetime gives an anonymous submission ownership before a thread exists.
enum ExecutionConversationIdentity: Hashable
{
	case newChat(lifetime: Int)
	case thread(String)

	var conversation: ConversationKey
	{
		switch self
		{
		case .newChat: return .newChat
		case .thread(let id): return .thread(id)
		}
	}

	func isOrdered(before other: ExecutionConversationIdentity) -> Bool
	{
		switch (self, other)
		{
		case (.thread(let lhs), .thread(let rhs)): return lhs < rhs
		case (.newChat(let lhs), .newChat(let rhs)): return lhs < rhs
		case (.thread, .newChat): return true
		case (.newChat, .thread): return false
		}
	}
}

struct ExecutionRegistry
{
	var entries: [ExecutionConversationIdentity: ExecutionModel] = [:]
	private var adoptedIdentities: [ExecutionConversationIdentity: ExecutionConversationIdentity] =
		[:]

	func canonicalIdentity(
		_ identity: ExecutionConversationIdentity
	) -> ExecutionConversationIdentity
	{
		adoptedIdentities[identity] ?? identity
	}

	func identity(for context: OperationContext) -> ExecutionConversationIdentity?
	{
		let matches = entries.filter
		{
			identity, execution in
			let matchesThread = context.threadID == nil
				|| identity.conversation.threadID == context.threadID
				|| execution.activeThreadID == context.threadID
			return matchesThread && execution.containsRequest(context)
		}
		guard matches.count == 1
		else
		{
			return nil
		}
		return matches.first?.key
	}

	mutating func adopt(
		_ source: ExecutionConversationIdentity,
		as destination: ExecutionConversationIdentity
	) -> Bool
	{
		guard source != destination
		else
		{
			return true
		}
		guard let execution = entries[source],
				entries[destination]?.isTaskActive != true,
				entries[destination]?.blocksCleanup != true
		else
		{
			return false
		}
		entries.removeValue(forKey: source)
		entries[destination] = execution
		adoptedIdentities[source] = destination
		return true
	}
}

extension ExecutionModel
{
	func containsRequest(_ context: OperationContext) -> Bool
	{
		let requests = [
			owner?.submission,
			submissionRequest,
			pendingSteering,
			stopContext,
			pendingInterruption?.context,
			pendingReconciliation?.context,
			pendingGitTurnBaselineCapture?.context
		]
		return requests.compactMap
		{
			$0
		}.contains
		{
			$0.isSameRequest(as: context)
		} || pendingResponses.values.contains
		{
			$0.context.isSameRequest(as: context)
		} || gitTurnBaselineBindings.values.contains
		{
			$0.context.isSameRequest(as: context)
		}
	}
}
