import Foundation

enum WorkspacePresentationCommand
{
	case openSignIn(URL)
	case slashCommand(SlashCommandPresentationRequest)
	case taskFinished
}

struct WorkspacePublication
{
	let model: WorkspaceModel
	let coalescible: Bool
	let commands: [WorkspacePresentationCommand]
}

@MainActor
final class WorkspacePublicationCoordinator
{
	private weak var store: WorkspaceStateStore?
	private var observerToken: UUID?
	private var pendingPublication: Task<Void, Never>?
	private let render: (ConversationSnapshot) -> Void
	private let handleCommand: (WorkspacePresentationCommand) -> Void

	init(
		store: WorkspaceStateStore,
		render: @escaping (ConversationSnapshot) -> Void,
		command: @escaping (WorkspacePresentationCommand) -> Void =
		{
			_ in
		}
	)
	{
		self.store = store
		self.render = render
		handleCommand = command

		observerToken = store.observePublications
		{
			[weak self] publication in
			self?.receive(publication)
		}
	}

	private func receive(_ publication: WorkspacePublication)
	{
		for presentationCommand in publication.commands
		{
			handleCommand(presentationCommand)
		}

		guard let store
		else
		{
			return
		}
		if !publication.coalescible
		{
			pendingPublication?.cancel()
			pendingPublication = nil
			render(store.currentSnapshot)
			return
		}
		scheduleCoalescedPublication(
			for: store,
			identity: publication.model.identity
		)
	}

	private func scheduleCoalescedPublication(
		for store: WorkspaceStateStore,
		identity: WorkspaceIdentity
	)
	{
		guard pendingPublication == nil
		else
		{
			return
		}

		pendingPublication = Task
		{
			[weak self, weak store] in
			guard let store
			else
			{
				return
			}
			await store.factoryDependencies.publicationWait()
			guard !Task.isCancelled, !store.isRetired, let self,
					store.model.identity == identity
			else
			{
				return
			}
			self.pendingPublication = nil
			self.render(store.currentSnapshot)
		}
	}

	func cancel()
	{
		pendingPublication?.cancel()
		pendingPublication = nil
		if let observerToken
		{
			store?.removePublicationObserver(observerToken)
		}
		observerToken = nil
	}

	deinit
	{
		pendingPublication?.cancel()
	}
}
