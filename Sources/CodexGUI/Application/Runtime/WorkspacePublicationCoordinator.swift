import Foundation

enum WorkspacePresentationCommand
{
	case openSignIn(URL)
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
	private var token: UUID?
	private var pending: Task<Void, Never>?
	private let render: (ConversationSnapshot) -> Void
	private let command: (WorkspacePresentationCommand) -> Void
	init(
		store: WorkspaceStateStore,
		render: @escaping (ConversationSnapshot) -> Void,
		command: @escaping (WorkspacePresentationCommand) -> Void =
		{
			_ in
		}
	)
	{
		self.store = store; self.render = render; self.command = command
		token = store.observePublications
		{
			[weak self] publication in self?.receive(publication)
		}
	}
	private func receive(_ publication: WorkspacePublication)
	{
		for value in publication.commands
		{
			command(value)
		}
		guard let store
		else
		{
			return
		}
		if !publication
			.coalescible
		{
			pending?.cancel(); pending = nil; render(store.currentSnapshot); return
		}
		guard pending == nil
		else
		{
			return
		}
		let identity = publication.model.identity
		pending = Task
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
			self.pending = nil; self.render(store.currentSnapshot)
		}
	}
	func cancel()
	{
		pending?.cancel(); pending = nil
		if let token
		{
			store?.removePublicationObserver(token)
		}; token = nil
	}
	deinit
	{
		pending?.cancel()
	}
}
