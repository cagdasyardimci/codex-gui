import Foundation

@testable import CodexGUI

/// Test harness for canonical store inputs and retained UI publication observations.
@MainActor
final class WorkspaceTestFixture
{
	let store: WorkspaceStateStore
	var inputs: WorkspaceStoreInputs
	{
		store.inputs
	}
	var currentSnapshot: ConversationSnapshot
	{
		store.currentSnapshot
	}
	var isTaskActive: Bool
	{
		selectors.isTaskActive
	}
	var selectedProjectURL: URL?
	{
		selectors.project
	}
	var managedTaskWorkspace: TaskWorkspace?
	{
		store.managedWorkspace
	}
	var pendingBackendOperationCount: Int
	{
		store.runningOperationCount
	}
	var backendDiagnosticsReport: String
	{
		selectors.backendDiagnosticsReport
	}
	var draftStorage: LocalStorage
	{
		store.factoryDependencies.storage
	}
	private var selectors: WorkspaceSelectors
	{
		WorkspaceSelectors(
			model: store.model,
			now: store.now()
		)
	}
	private var publication: WorkspacePublicationCoordinator?
	var onChange: ((ConversationSnapshot) -> Void)?
	{
		didSet
		{
			attachPublication()
		}
	}
	var onTaskFinished: (() -> Void)?
	{
		didSet
		{
			attachPublication()
		}
	}

	init(store: WorkspaceStateStore)
	{
		self.store = store
	}

	convenience init(
		server: any CodexService = AppServer(),
		storage: LocalStorage = LocalStorage(),
		reviewMarkerStore: ReviewMarkerStore = ReviewMarkerStore(),
		projectContextStore: ProjectContextStore = ProjectContextStore(),
		taskWorkspace: TaskWorkspace? = nil,
		taskWorkspaceManager: GitWorktreeManager? = nil,
		usageFreshnessDuration: TimeInterval = 900,
		usageRuntime: UsageRuntime? = nil,
		publicationWait: @escaping @MainActor () async -> Void =
		{
			try? await Task.sleep(for: .milliseconds(50))
		}
	)
	{
		let dependencies = WorkspaceStoreDependencies(
			service: server,
			storage: storage,
			reviewMarkerStore: reviewMarkerStore,
			projectContextStore: projectContextStore,
			manager: taskWorkspaceManager,
			usageRuntime: usageRuntime,
			usageFreshnessDuration: usageFreshnessDuration,
			publicationWait: publicationWait
		)
		if let workspace = taskWorkspace
		{
			self.init(store: Self.makeManagedStore(
				for: workspace,
				dependencies: dependencies
			))
		}
		else
		{
			self.init(store: WorkspaceStoreFactory.makeSource(dependencies: dependencies))
		}
	}

	private static func makeManagedStore(
		for workspace: TaskWorkspace,
		dependencies: WorkspaceStoreDependencies
	) -> WorkspaceStateStore
	{
		let sessionID = UUID()
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: workspace.id,
				sessionID: sessionID
			),
			workspace: WorkspaceIdentity(
				sessionID: sessionID,
				canonicalCheckoutPath: workspace.checkoutPath
			)
		)
		let configuration = WorkspaceStoreConfiguration(
			reference: reference,
			managedWorkspace: workspace
		)
		return WorkspaceStoreFactory.make(
			configuration: configuration,
			dependencies: dependencies
		)
	}

	private func attachPublication()
	{
		let shouldAttachPublication =
			publication == nil && (onChange != nil || onTaskFinished != nil)
		guard shouldAttachPublication
		else
		{
			return
		}
		publication = WorkspacePublicationCoordinator(
			store: store,
			render:
			{
				[weak self] in
				self?.onChange?($0)
			},
			command:
			{
				[weak self] command in
				if case .taskFinished = command
				{
					self?.onTaskFinished?()
				}
			}
		)
	}

	func beginWorkspaceCleanup() -> Bool
	{
		guard let managed = store.managedWorkspace
		else
		{
			return false
		}
		return store.reserveCleanup(WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: WorkspaceLifecycleReducer
				.reference(store.model),
			expected: managed
		))
	}

	func finishWorkspaceCleanup()
	{
		if let request = store.model.lifecycle.cleanupReservation
		{
			store.releaseCleanup(request)
		}
	}

	func shutdown()
	{
		publication?.cancel()
		publication = nil
		store.shutdown()
	}
}

@MainActor
func observedQuitOutcome(
	_ coordinator: TaskWorkspaceCoordinator,
	confirm: @escaping @MainActor (WorkspaceQuitRequest) -> Bool
) async -> (WorkspaceQuitRequest, Bool)
{
	await withCheckedContinuation
	{
		continuation in
		coordinator.onConfirmQuit =
		{
			coordinator.confirmQuit(
				$0,
				approved: confirm($0)
			)
		}
		coordinator.onQuitCompleted =
		{
			[weak coordinator] request, approved in
			coordinator?.onConfirmQuit = nil
			coordinator?.onQuitCompleted = nil
			continuation.resume(returning: (request, approved))
		}
		coordinator.requestQuit()
	}
}
