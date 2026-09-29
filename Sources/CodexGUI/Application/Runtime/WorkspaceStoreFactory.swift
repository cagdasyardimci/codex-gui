import Foundation

struct WorkspaceStoreConfiguration
{
	let reference: WorkspaceLifecycleOwnerReference
	var managedWorkspace: TaskWorkspace? = nil
}

@MainActor
struct WorkspaceStoreDependencies
{
	let service: any CodexService
	let storage: LocalStorage
	let reviewMarkerStore: ReviewMarkerStore
	let projectContextStore: ProjectContextStore
	let manager: GitWorktreeManager?
	let usageRuntime: UsageRuntime
	let publicationWait: @MainActor () async -> Void
	init(
		service: any CodexService = AppServer(),
		storage: LocalStorage = LocalStorage(),
		reviewMarkerStore: ReviewMarkerStore = ReviewMarkerStore(),
		projectContextStore: ProjectContextStore = ProjectContextStore(),
		manager: GitWorktreeManager? = nil,
		usageRuntime: UsageRuntime? = nil,
		usageFreshnessDuration: TimeInterval = 900,
		publicationWait: @escaping @MainActor () async
			-> Void =
			{
				try? await Task.sleep(for: .milliseconds(50))
			}
	)
	{
		self.service = service; self.storage = storage; self.reviewMarkerStore = reviewMarkerStore
		self.projectContextStore = projectContextStore; self.manager = manager
		self.usageRuntime = usageRuntime ?? UsageRuntime(freshnessDuration: usageFreshnessDuration)
		self.publicationWait = publicationWait
	}
	func replacing(
		service: any CodexService,
		manager: GitWorktreeManager?
	) -> Self
	{
		Self(
			service: service,
			storage: storage,
			reviewMarkerStore: reviewMarkerStore,
			projectContextStore: projectContextStore,
			manager: manager,
			usageRuntime: usageRuntime,
			publicationWait: publicationWait
		)
	}
}

@MainActor
enum WorkspaceStoreFactory
{
	static func makeSource(
		dependencies: WorkspaceStoreDependencies = WorkspaceStoreDependencies(),
		sessionID: UUID = UUID()
	) -> WorkspaceStateStore
	{
		let store = make(
			configuration: WorkspaceStoreConfiguration(
				reference: WorkspaceLifecycleOwnerReference(
					owner: .source(sessionID: sessionID),
					workspace: WorkspaceIdentity(
						sessionID: sessionID,
						canonicalCheckoutPath: nil
					)
				)
			),
			dependencies: dependencies
		)
		WorkspaceHydration.restoreSourceStartup(store)
		return store
	}

	static func make(
		configuration: WorkspaceStoreConfiguration,
		dependencies: WorkspaceStoreDependencies
	) -> WorkspaceStateStore
	{
		var model = WorkspaceModel(identity: configuration.reference.workspace)
		model.lifecycle.owner = configuration.reference.owner
		model.lifecycle.managedWorkspace = configuration.managedWorkspace
		model.conversations.boundThreadID = configuration.managedWorkspace?.threadID
		let selected = configuration.managedWorkspace?.threadID
		model.conversations.selectedConversation = selected.map(ConversationKey.thread) ?? .newChat
		let store = WorkspaceStateStore(
			model: model,
			service: dependencies.service,
			storage: dependencies.storage,
			reviewMarkerStore: dependencies.reviewMarkerStore,
			taskWorkspace: configuration.managedWorkspace,
			taskWorkspaceManager: dependencies.manager,
			persistence: dependencies.storage.workspacePersistenceScheduler,
			projectContextStore: dependencies.projectContextStore,
			reducers: [ConnectionReducer.reducer,
						ExecutionReducer.reducer,
						ComposerReducer.reducer,
						ConversationReducer.reducer,
						ReviewReducer.reducer,
						ContextNavigationReducer.reducer,
						PreferenceReducer.reducer,
						UsageReducer.reducer,
						WorkspaceLifecycleReducer.reducer],
			reduceDomainEvent: WorkspaceDomainComposition.reduceDomainEvent,
			usageRuntime: dependencies.usageRuntime,
			factoryDependencies: dependencies,
			mapEvent:
			{
				context, event in
				let observation = OperationContext(
					workspace: context.workspace,
					generation: context.generation,
					requestID: UUID()
				)
				var actions: [WorkspaceAction] =
					[.execution(.backendObserved(
						observation,
						event
					))]
				if case .accountUpdated = event
				{
					actions
						.append(.preferences(.accountRefreshRequested(observation)))
				}
				if case .skillsChanged = event
				{
					actions
						.append(.contextNavigation(.skillsInvalidated(observation)))
				}
				return actions
			}
		)
		WorkspaceHydration.initialize(store)
		return store
	}
}
