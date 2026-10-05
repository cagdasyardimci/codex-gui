import Foundation

/// Binds the auxiliary reader to one parent presentation and the existing backend subscription.
@MainActor
final class SubagentConversationSession
{
	weak var controller: SubagentsViewController?
	let runtime: SubagentConversationRuntime
	var acceptsOwner: () -> Bool =
	{
		false
	}
	private weak var store: WorkspaceStateStore?
	private var eventObserver: UUID?

	init(
		controller: SubagentsViewController,
		store: WorkspaceStateStore
	)
	{
		self.controller = controller
		self.store = store
		runtime = SubagentConversationRuntime(
			service: store.factoryDependencies.service,
			projectPath: controller.owner.projectPath
		)
		runtime.onChange =
		{
			[weak self, weak controller] state in
			guard let self, let controller, self.acceptsOwner()
			else
			{
				return
			}
			if let agent = state.agent
			{
				controller.showConversation(
					agent: agent,
					state: state
				)
			}
			else
			{
				controller.showList()
			}
		}
		eventObserver = store.observeBackendEvents
		{
			[weak self] event in
			guard let self, self.acceptsOwner()
			else
			{
				return
			}
			self.runtime.receive(event)
		}
	}

	func invalidate()
	{
		if let eventObserver
		{
			store?.removeBackendEventObserver(eventObserver)
		}
		eventObserver = nil
		acceptsOwner =
		{
			false
		}
		runtime.invalidate()
	}
}
