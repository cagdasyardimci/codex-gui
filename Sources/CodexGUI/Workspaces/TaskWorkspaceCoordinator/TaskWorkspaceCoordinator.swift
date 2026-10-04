import Foundation

struct WorkspaceModalCapture: Equatable
{
	let reference: WorkspaceLifecycleOwnerReference
	let selectionEpoch: Int
	let conversation: ConversationKey
	let draftLifetime: Int
}

/// Coordinates value transitions. Registered stores own backend connections and feature values.
@MainActor
final class TaskWorkspaceCoordinator
{
	typealias StoreFactory = (WorkspaceStoreConfiguration) -> WorkspaceStateStore
	var onChange: ((ConversationSnapshot) -> Void)?
	var onTaskSnapshot: ((ConversationSnapshot) -> Void)?
	var onAllTasksFinished: (() -> Void)?
	var onStopAllFailed: (() -> Void)?
	var onConfirmQuit: ((WorkspaceQuitRequest) -> Void)?
	var onQuitCompleted: ((WorkspaceQuitRequest, Bool) -> Void)?
	var onPresentationCommand: ((WorkspacePresentationCommand) -> Void)?
	let sourceStore: WorkspaceStateStore
	private(set) var model: WorkspaceCoordinatorModel
	let manager: GitWorktreeManager
	let makeStore: StoreFactory
	var stores: [WorkspaceLifecycleOwner: WorkspaceStateStore] = [:]
	var tokens: [WorkspaceLifecycleOwner: UUID] = [:]
	var publicationTokens: [WorkspaceLifecycleOwner: UUID] = [:]
	var pendingPublication: Task<Void, Never>?
	var taskPresentationCache = TaskWorkspacePresentationCache()
	var jobs: [UUID: [UUID: Task<Void, Never>]] = [:]
	private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
	var dispatchDepth = 0
	var retired = false

	init(
		sourceStore: WorkspaceStateStore,
		manager: GitWorktreeManager = GitWorktreeManager(),
		makeStore: StoreFactory? = nil
	)
	{
		self.sourceStore = sourceStore
		self.manager = manager
		self.makeStore = makeStore ??
		{
			configuration in
			WorkspaceStoreFactory.make(
				configuration: configuration,
				dependencies: sourceStore.factoryDependencies.replacing(
					service: AppServer(),
					manager: manager
				)
			)
		}
		model = WorkspaceCoordinatorModel(source: sourceStore.model.identity)
		register(
			sourceStore,
			owner: model.selectedOwner
		)
	}

	var selectedStore: WorkspaceStateStore
	{
		stores[model.selectedOwner] ?? sourceStore
	}

	var selectedProjectURL: URL?
	{
		selectedStore.model.identity.canonicalCheckoutPath.map
		{
			URL(fileURLWithPath: $0)
		}
	}

	var sourceProjectURL: URL?
	{
		model.source.canonicalCheckoutPath.map
		{
			URL(fileURLWithPath: $0)
		}
	}

	var isTaskActive: Bool
	{
		model.hasRemoteOwners
	}

	var hasUncertainActiveTask: Bool
	{
		model.hasUncertainOwners
	}

	var currentSnapshot: ConversationSnapshot
	{
		decorated(
			selectedStore.currentSnapshot,
			owner: model.selectedOwner
		)
	}

	func store(for reference: WorkspaceLifecycleOwnerReference) -> WorkspaceStateStore?
	{
		guard let store = stores[reference.owner],
				store.model.identity == reference.workspace
		else
		{
			return nil
		}
		return store
	}

	func store(owningThread id: String) -> WorkspaceStateStore?
	{
		let matches = stores.values.filter
		{
			$0.model.execution.activeThreadID == id || $0.currentSnapshot
				.selectedThreadID == id || $0.managedWorkspace?.threadID == id
		}
		return matches.count == 1 ? matches.first : nil
	}

	func captureSelectedOwner() -> WorkspaceModalCapture
	{
		let snapshot = currentSnapshot
		return WorkspaceModalCapture(
			reference: WorkspaceLifecycleOwnerReference(
				owner: model.selectedOwner,
				workspace: selectedStore.model.identity
			),
			selectionEpoch: model.selectionEpoch,
			conversation: snapshot.selectedThreadID.map(ConversationKey.thread) ?? .newChat,
			draftLifetime: snapshot.composerDraftLifetime
		)
	}

	func matches(_ capture: WorkspaceModalCapture) -> Bool
	{
		capture == captureSelectedOwner() &&
			store(for: capture.reference) != nil
	}

	func start()
	{
		sourceStore.inputs.start()
		Task
		{
			await self.reloadWorkspaces()
		}
	}

	func shutdown()
	{
		retired = true
		retireRegisteredStores()
		cancelLifecycleJobs()
	}

	private func retireRegisteredStores()
	{
		for (owner, store) in stores
		{
			if let token = tokens[owner]
			{
				store.removeObserver(token)
			}
			if let token = publicationTokens[owner]
			{
				store.removePublicationObserver(token)
			}
			store.shutdown()
		}
		tokens.removeAll()
		publicationTokens.removeAll()
		pendingPublication?.cancel()
		stores.removeAll()
	}

	private func cancelLifecycleJobs()
	{
		for group in jobs.values
		{
			for job in group.values
			{
				job.cancel()
			}
		}
	}

	func openProject(_ url: URL)
	{
		var proposed = model
		_ = WorkspaceCoordinatorReducer.reduce(
			&proposed,
			.sourceOpened(model.source)
		)
		guard proposed.selectionEpoch != model.selectionEpoch
		else
		{
			return
		}
		// The store effect validates and resolves the target. Its accepted result owns adoption.
		dispatchDepth += 1
		defer
		{
			dispatchDepth -= 1
			if dispatchDepth == 0
			{
				pendingPublication?.cancel()
				pendingPublication = nil
				onChange?(currentSnapshot)
			}
		}
		sourceStore.inputs.openProject(url)
	}

	func selectSourceCheckout()
	{
		dispatch(.sourceSelected)
	}

	@discardableResult func createTask(named name: String) async -> TaskWorkspace?
	{
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		let request = WorkspaceCreationRequest(
			requestID: UUID(),
			source: model.source,
			selectionEpoch: model.selectionEpoch,
			taskID: "\(trimmed)|\(UUID().uuidString)",
			name: trimmed,
			ownerSessionID: UUID()
		)
		dispatch(.creationRequested(request))
		await wait(request.requestID)
		return model.workspaces.values.first
		{
			$0.taskID == request.taskID
		}
	}

	func reloadWorkspaces() async
	{
		let request = WorkspaceRecoveryRequest(
			requestID: UUID(),
			recordsRevision: model.recordsRevision
		)
		dispatch(.recoveryRequested(request))
		await wait(request.requestID)
	}

	func selectWorkspace(_ id: UUID) async
	{
		guard let expected = model.workspaces[id]
		else
		{
			return
		}
		let session = stores.keys.first
		{
			if case .managed(
				let workspaceID,
				_
			) = $0
			{
				return workspaceID == id
			}
			return false
		}?
		.sessionID ?? UUID()
		let request = WorkspaceSelectionRequest(
			requestID: UUID(),
			ownerSessionID: session,
			selectionEpoch: model.selectionEpoch + 1,
			expected: expected
		)
		dispatch(.selectionRequested(request))
		await wait(request.requestID)
	}

	func removeCheckout(id: UUID) async
	{
		if model.pendingCleanup[id]?.stage == .recovering
		{
			await reloadWorkspaces()
		}
		guard let expected = model.workspaces[id]
		else
		{
			return
		}
		let owner = stores.keys.first
		{
			if case .managed(
				let workspaceID,
				_
			) = $0
			{
				return workspaceID == id
			}
			return false
		}
		let reference = owner.flatMap
		{
			owner in stores[owner].map
			{
				WorkspaceLifecycleOwnerReference(
					owner: owner,
					workspace: $0.model.identity
				)
			}
		}
		let request = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: reference,
			expected: expected
		)
		dispatch(.cleanupRequested(request))
		await wait(request.requestID)
	}

	func cancelIncompleteCreation(id: UUID) async
	{
		guard let expected = model.workspaces[id]
		else
		{
			return
		}
		let requestID = UUID()
		dispatch(.cancellationRequested(
			requestID: requestID,
			expected: expected
		))
		await wait(requestID)
	}

	func selectThread(_ id: String)
	{
		let managed = model.workspaces.values.filter
		{
			$0.phase == .active && $0.threadID == id
		}
		let source = sourceStore.currentSnapshot
		let belongsToSource = source.activeThreadID == id || source.selectedThreadID == id || source
			.threads.contains
			{
				$0.id == id
			}
		guard managed.count + (belongsToSource ? 1 : 0) == 1
		else
		{
			return
		}
		if let workspace = managed.first
		{
			Task
			{
				await self.selectWorkspace(workspace.id)
				guard case .managed(
					let selected,
					_
				) = self.model.selectedOwner,
					selected == workspace.id
				else
				{
					return
				}
				self.selectedStore.inputs.selectThread(id)
			}
		}
		else
		{
			selectSourceCheckout()
			sourceStore.inputs.selectThread(id)
		}
	}

	func selectThread(
		_ id: String,
		owner reference: WorkspaceLifecycleOwnerReference
	)
	{
		guard let captured = store(for: reference)
		else
		{
			return
		}
		switch reference.owner
		{
		case .source:
			let snapshot = captured.currentSnapshot
			guard snapshot.activeThreadID == id || snapshot.selectedThreadID == id || snapshot
				.threads.contains(where:
					{
						$0.id == id
					})
			else
			{
				return
			}
			selectSourceCheckout()
			captured.inputs.selectThread(id)
		case .managed(
			let workspaceID,
			_
		):
			guard let expected = model.workspaces[workspaceID], expected.phase == .active,
					expected.checkoutPath == reference.workspace.canonicalCheckoutPath,
					expected.threadID == id
			else
			{
				return
			}
			Task
			{
				await self.selectWorkspace(workspaceID)
				guard self.model.selectedOwner == reference.owner,
						self.store(for: reference) === captured,
						self.model.workspaces[workspaceID] == expected
				else
				{
					return
				}
				captured.inputs.selectThread(id)
			}
		}
	}

	@discardableResult func requestQuit() -> WorkspaceQuitRequest
	{
		let request = WorkspaceQuitRequest(requestID: UUID())
		dispatch(.quitRequested(request))
		return request
	}

	func confirmQuit(
		_ request: WorkspaceQuitRequest,
		approved: Bool
	)
	{
		dispatch(.quitConfirmationFinished(
			request,
			approved: approved
		))
	}

	func stopAll()
	{
		let request = WorkspaceQuitRequest(
			requestID: UUID(),
			purpose: .stopAll
		)
		dispatch(.quitRequested(request))
		if case .confirming(let pending) = model.quit, pending == request
		{
			confirmQuit(
				request,
				approved: true
			)
		}
	}

	func dispatch(
		_ action: WorkspaceCoordinatorAction,
		publish: Bool = true
	)
	{
		guard !retired
		else
		{
			return
		}
		dispatchDepth += 1
		let effects = WorkspaceCoordinatorReducer.reduce(
			&model,
			action
		)
		for effect in effects
		{
			perform(effect)
		}
		dispatchDepth -= 1
		if dispatchDepth == 0,
			publish
		{
			pendingPublication?.cancel()
			pendingPublication = nil
			onChange?(currentSnapshot)
		}
	}

	func launch(
		_ requestID: UUID,
		operation: @escaping @MainActor () async -> Void
	)
	{
		let jobID = UUID()
		let task = Task
		{
			await operation()
			self.jobs[requestID]?.removeValue(forKey: jobID)
			if self.jobs[requestID]?.isEmpty == true
			{
				self.jobs.removeValue(forKey: requestID)
				for waiter in self.waiters.removeValue(forKey: requestID) ?? []
				{
					waiter.resume()
				}
			}
		}
		jobs[requestID, default: [:]][jobID] = task
	}

	func wait(_ requestID: UUID) async
	{
		guard jobs[requestID]?.isEmpty == false
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters[requestID, default: []].append($0)
		}
	}
}
