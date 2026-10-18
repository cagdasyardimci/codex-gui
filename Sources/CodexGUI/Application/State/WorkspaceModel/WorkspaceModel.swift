import Foundation

/// Connection, execution, and composer are canonical reducer-owned values.
/// Canonical feature values are reduced together before observers are notified.
struct WorkspaceModel
{
	var identity: WorkspaceIdentity
	var lifecycle = WorkspaceLifecycleModel()
	var connection = ConnectionModel()
	var executions = ExecutionRegistry()
	private var executionReductionIdentity: ExecutionConversationIdentity?
	/// Publications project the displayed conversation; reductions use captured ownership.
	var execution: ExecutionModel
	{
		get
		{
			let identity = executionReductionIdentity.map(executions.canonicalIdentity)
				?? selectedExecutionIdentity
			return executions.entries[identity] ?? emptyExecution
		}
		set
		{
			let identity = executionReductionIdentity.map(executions.canonicalIdentity)
				?? selectedExecutionIdentity
			executions.entries[identity] = newValue
		}
	}
	var composer = ComposerModel()
	var composerCommands = ComposerCommandModel()
	var conversations = ConversationsModel()
	var review = ReviewModel()
	var contextNavigation = ContextNavigationModel()
	var preferences = PreferencesModel()
	var usage = UsageModel()

	init(identity: WorkspaceIdentity)
	{
		self.identity = identity
	}

	var selectedExecutionIdentity: ExecutionConversationIdentity
	{
		executionIdentity(for: conversations.selectedConversation)
	}

	func executionIdentity(for conversation: ConversationKey) -> ExecutionConversationIdentity
	{
		switch conversation
		{
		case .thread(let id): return .thread(id)
		case .newChat:
			return .newChat(lifetime: max(
				composer.drafts[.newChat]?.lifetime ?? 0,
				composer.pendingNewChatLifetime ?? 0
			))
		}
	}

	private var emptyExecution: ExecutionModel
	{
		var value = ExecutionModel()
		value.state = connection.isConnected ? .ready : .disconnected
		return value
	}

	@MainActor
	mutating func reduceExecutionScope(
		_ identity: ExecutionConversationIdentity?,
		body: @MainActor (inout WorkspaceModel) -> WorkspaceReduction
	) -> WorkspaceReduction
	{
		let previous = executionReductionIdentity
		if let identity
		{
			executionReductionIdentity = executions.canonicalIdentity(identity)
		}
		defer
		{
			executionReductionIdentity = previous.map(executions.canonicalIdentity)
		}
		return body(&self)
	}

	mutating func adoptExecution(
		for context: OperationContext,
		threadID: String
	) -> Bool
	{
		guard let source = executions.identity(for: context)
		else
		{
			return false
		}
		let destination = ExecutionConversationIdentity.thread(threadID)
		guard executions.adopt(
			source,
			as: destination
		)
		else
		{
			return false
		}
		if executionReductionIdentity.map(executions.canonicalIdentity) == destination
		{
			executionReductionIdentity = destination
		}
		return true
	}

	func execution(for conversation: ConversationKey) -> ExecutionModel
	{
		executions.entries[executionIdentity(for: conversation)] ?? emptyExecution
	}

	func execution(for context: OperationContext) -> ExecutionModel?
	{
		guard context.belongsTo(
			workspace: identity,
			generation: connection.generation
		)
		else
		{
			return nil
		}
		if let owner = executions.identity(for: context)
		{
			return executions.entries[owner]
		}
		return context.threadID.flatMap
		{
			executions.entries[.thread($0)]
		}
	}

	var allExecutions: [ExecutionModel]
	{
		executions.entries.keys.sorted
		{
			$0.isOrdered(before: $1)
		}.compactMap
		{
			executions.entries[$0]
		}
	}

	var hasActiveExecution: Bool
	{
		executions.entries.values.contains(where: \.isTaskActive)
	}

	var blocksExecutionCleanup: Bool
	{
		executions.entries.values.contains(where: \.blocksCleanup)
	}

	var hasExecutionReconciliation: Bool
	{
		executions.entries.values.contains(where: \.needsReconciliation)
	}

	var hasUncertainExecutionRequest: Bool
	{
		executions.entries.values.contains(where: \.hasUncertainRequest)
	}

	var pendingCommandOwnership: [TaskCommandOwnership]
	{
		allExecutions.flatMap
		{
			Array($0.commandLifetime.pending)
		}.sorted
		{
			if $0.threadID != $1.threadID
			{
				return $0.threadID < $1.threadID
			}
			if $0.turnID != $1.turnID
			{
				return $0.turnID < $1.turnID
			}
			return $0.itemID < $1.itemID
		}
	}

	var executionRecoveryThreadIDs: [String]
	{
		var threadIDs = Set(pendingCommandOwnership.map(\.threadID))
		for execution in allExecutions where execution.blocksCleanup
		{
			if let threadID = execution.activeThreadID ?? execution.owner?.submission.threadID
			{
				threadIDs.insert(threadID)
			}
		}
		return threadIDs.sorted()
	}

	mutating func updateAllExecutions(_ update: (inout ExecutionModel) -> Void)
	{
		if executions.entries[selectedExecutionIdentity] == nil
		{
			executions.entries[selectedExecutionIdentity] = emptyExecution
		}
		for identity in executions.entries.keys.sorted(by:
			{
				$0.isOrdered(before: $1)
			})
		{
			update(&executions.entries[identity]!)
		}
	}
}
