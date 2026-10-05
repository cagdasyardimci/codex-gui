import AppKit

extension MainWindowController
{
	func configureSubagentConversationNavigation(
		owner: FeaturePresentationOwner,
		target: WorkspaceIntentTarget
	)
	{
		guard let controller = inspector.conversationSubagents, controller.owner == owner
		else
		{
			subagentConversationSession?.invalidate()
			subagentConversationSession = nil
			conversation.onSelectSubagentThread = nil
			return
		}
		if subagentConversationSession?.controller !== controller
		{
			subagentConversationSession?.invalidate()
			subagentConversationSession = SubagentConversationSession(
				controller: controller,
				store: target.store
			)
		}
		guard let session = subagentConversationSession
		else
		{
			return
		}
		let acceptsOwner: () -> Bool =
		{
			[weak self, weak controller] in
			guard let self, let controller
			else
			{
				return false
			}
			return self.currentStore === target.store && !target.store.isRetired
				&& target.accepts(.loadEarlierTurns) && self.summaryReconciliation.owner == owner
				&& self.inspector.conversationSubagents === controller
		}
		session.acceptsOwner = acceptsOwner
		let openConversation: (String) -> Void =
		{
			[weak self, weak controller, weak session] threadID in
			guard let self, let controller, let session, acceptsOwner(),
					let agent = controller.subagents.agents.first(where:
					{
						$0.conversationThreadID == threadID
					})
			else
			{
				return
			}
			self.openSubagentsToolTab(ContextPanelRequest(
				owner: owner,
				destination: .subagents
			))
			// The auxiliary reader leaves parent selection, drafts and execution untouched.
			session.runtime.select(agent)
		}
		controller.onSelectThread = openConversation
		conversation.onSelectSubagentThread = openConversation
		controller.onBack =
		{
			[weak session] in session?.runtime.back()
		}
		controller.onLoadEarlierTurns =
		{
			[weak session] in
			if acceptsOwner()
			{
				session?.runtime.loadEarlierTurns()
			}
		}
		controller.onRetry =
		{
			[weak session] in
			if acceptsOwner()
			{
				session?.runtime.retry()
			}
		}
		inspector.toolsTabs.onSubagentsTabClosed =
		{
			[weak controller, weak session] in
			session?.runtime.back()
			controller?.showList()
		}
	}
}
