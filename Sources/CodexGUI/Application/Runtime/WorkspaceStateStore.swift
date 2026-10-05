import Foundation

/// Reducer dependencies are synchronous. Actions and effects contain only semantic values.
@MainActor
struct WorkspaceReducer
{
	let reduce: @MainActor (
		inout WorkspaceModel,
		WorkspaceAction
	) -> WorkspaceReduction

	init(reduce: @escaping @MainActor (
		inout WorkspaceModel,
		WorkspaceAction
	) -> WorkspaceReduction)
	{
		self.reduce = reduce
	}

	init(reduceEffects: @escaping @MainActor (
		inout WorkspaceModel,
		WorkspaceAction
	) -> [WorkspaceEffect])
	{
		reduce =
		{
			model, action in
			WorkspaceReduction(effects: reduceEffects(
				&model,
				action
			))
		}
	}
}

@MainActor
final class WorkspaceStateStore
{
	private(set) var model: WorkspaceModel
	private let reducers: [WorkspaceReducer]
	private let makeRequestID: () -> UUID
	private let reduceDomainEvent: @MainActor (
		inout WorkspaceModel,
		WorkspaceDomainEvent
	) -> WorkspaceReduction
	private struct QueuedAction
	{
		let action: WorkspaceAction
		let afterReduction: () -> Void
	}

	private var queuedActions: [QueuedAction] = []
	private var isDraining = false
	private var isShutdown = false
	private var observers: [UUID: (WorkspaceModel) -> Void] = [:]
	private var observerOrder: [UUID] = []
	private var runner: WorkspaceEffectRunner!
	private weak var preferenceStorage: LocalStorage?
	private var preferenceObserver: UUID?
	let factoryDependencies: WorkspaceStoreDependencies
	private var publicationObservers: [UUID: (WorkspacePublication) -> Void] = [:]
	var isRetired: Bool
	{
		isShutdown
	}
	var inputs: WorkspaceStoreInputs
	{
		WorkspaceStoreInputs(store: self)
	}
	var managedWorkspace: TaskWorkspace?
	{
		model.lifecycle.managedWorkspace
	}

	func now() -> Date
	{
		factoryDependencies.usageRuntime.now()
	}
	var currentSnapshot: ConversationSnapshot
	{
		WorkspaceSelectors.snapshot(
			model: model,
			now: now()
		)
	}
	var lifecycleObservation: WorkspaceLifecycleObservation
	{
		WorkspaceLifecycleObservation(
			reference: WorkspaceLifecycleReducer.reference(model),
			executionState: model.execution.state,
			activeThreadID: model.execution.activeThreadID,
			unresolvedCommands: model.execution.commandLifetime
				.hasPendingCommands,
			remoteOutcomeUncertain: model.execution.hasUncertainRequest
				|| model.composerCommands.uncertainFork != nil || model.lifecycle
				.managedOwnershipConflict != nil,
			needsReconciliation: model.execution.needsReconciliation,
			composerOutcomeUncertain: WorkspaceLifecycleReducer
				.hasUnresolvedComposer(model),
			pendingLocalWrites: runner
				.pendingAcceptedPersistenceCount > 0,
			managementInProgress: model.conversations
				.pendingManagement != nil || model.composerCommands.blocksNewWork,
			cleanupReservation: model.lifecycle.cleanupReservation?
				.requestID
		)
	}

	func reserveCleanup(_ request: WorkspaceCleanupRequest) -> Bool
	{
		guard !isDraining, !isShutdown
		else
		{
			return false
		}
		dispatch(.workspaceLifecycle(.cleanupReserved(request)))
		return model.lifecycle.cleanupReservation == request
	}

	func acceptRecoveredManagedRecord(
		_ reference: WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		recovered: TaskWorkspace
	)
	{
		dispatch(.workspaceLifecycle(.managedRecordRecovered(
			reference,
			expected: expected,
			recovered: recovered
		)))
	}

	func acceptManagedRecordRecoveryConflict(
		_ reference: WorkspaceLifecycleOwnerReference,
		expected: TaskWorkspace,
		cleanup: WorkspaceCleanupRequest?,
		message: String
	)
	{
		dispatch(.workspaceLifecycle(.managedRecordRecoveryConflicted(
			reference,
			expected: expected,
			cleanup: cleanup,
			message: message
		)))
	}

	func releaseCleanup(_ request: WorkspaceCleanupRequest)
	{
		dispatch(.workspaceLifecycle(.cleanupReleased(request)))
	}

	func freezeInputsForQuit(_ request: WorkspaceQuitRequest) -> Bool
	{
		let reference = WorkspaceLifecycleReducer.reference(model)
		if !isShutdown, model.lifecycle.quitReservation == WorkspaceQuitReservation(
			requestID: request.requestID,
			reference: reference
		)
		{
			return true
		}
		guard !isDraining, !isShutdown
		else
		{
			return false
		}
		dispatch(.workspaceLifecycle(.quitFrozen(
			request,
			reference
		)))
		return model.lifecycle.quitReservation == WorkspaceQuitReservation(
			requestID: request.requestID,
			reference: reference
		)
	}

	func thawInputsAfterQuit(_ request: WorkspaceQuitRequest)
	{
		dispatch(.workspaceLifecycle(.quitThawed(
			request,
			WorkspaceLifecycleReducer.reference(model)
		)))
	}

	func awaitAcceptedPersistence() async throws
	{
		try await runner.awaitAcceptedPersistence()
		if let message = WorkspaceLifecycleComposition
			.persistenceFailure(model)
		{
			throw WorkspacePersistenceBarrierError(message: message)
		}
	}

	func drainPersistence(projectPath: String? = nil) async throws
	{
		try await runner.drainPersistence(projectPath: projectPath)
	}

	@discardableResult
	func observePublications(_ observer: @escaping (WorkspacePublication) -> Void) -> UUID
	{
		let id = UUID()
		guard !isShutdown
		else
		{
			return id
		}
		publicationObservers[id] = observer
		observer(WorkspacePublication(
			model: model,
			coalescible: false,
			commands: []
		))
		return id
	}

	func removePublicationObserver(_ id: UUID)
	{
		publicationObservers.removeValue(forKey: id)
	}

	init(
		model: WorkspaceModel,
		service: any CodexService,
		gitTurnBaselineService: any GitTurnBaselineService = LocalGitTurnBaselineService.shared,
		storage: LocalStorage? = nil,
		reviewMarkerStore: ReviewMarkerStore? = nil,
		taskWorkspace: TaskWorkspace? = nil,
		taskWorkspaceManager: GitWorktreeManager? = nil,
		persistence: WorkspacePersistenceScheduler,
		projectContextStore: ProjectContextStore = ProjectContextStore(),
		reducers: [WorkspaceReducer] = [],
		reduceDomainEvent: @escaping @MainActor (
			inout WorkspaceModel,
			WorkspaceDomainEvent
		) -> WorkspaceReduction =
		{
			_, _ in WorkspaceReduction()
		},
		completedRequestLimit: Int = 128,
		usageRuntime: UsageRuntime = UsageRuntime(),
		previewPreparer: any ConversationPreviewPreparing = ConversationTextPreviewPreparer(),
		factoryDependencies: WorkspaceStoreDependencies? = nil,
		makeRequestID: @escaping () -> UUID = UUID.init,
		mapEvent: @escaping (
			OperationContext,
			AppServerEvent
		) -> [WorkspaceAction] =
		{
			_, _ in []
		}
	)
	{
		self.model = model
		self.model.lifecycle.managedWorkspace = self.model.lifecycle
			.managedWorkspace ?? taskWorkspace
		self.factoryDependencies = factoryDependencies ?? WorkspaceStoreDependencies(
			service: service,
			storage: storage ?? LocalStorage(),
			reviewMarkerStore: reviewMarkerStore ?? ReviewMarkerStore(),
			projectContextStore: projectContextStore,
			manager: taskWorkspaceManager,
			usageRuntime: usageRuntime,
			previewPreparer: previewPreparer
		)
		self.reducers = reducers
		self.reduceDomainEvent = reduceDomainEvent
		self.makeRequestID = makeRequestID
		runner = WorkspaceEffectRunner(
			service: service,
			gitTurnBaselineService: gitTurnBaselineService,
			isSubmissionCurrent:
			{
				[weak self] context in
				guard let self, !self.isShutdown
				else
				{
					return false
				}
				return context.belongsTo(
					workspace: self.model.identity,
					generation: self.model.connection.generation
				) && self.model.execution.owner?.submission.isSameRequest(as: context) == true
			},
			isSubmissionStopped:
			{
				[weak self] context in
				guard let self, !self.isShutdown
				else
				{
					return false
				}
				return self.model.execution.stopRequested
					&& self.model.execution.owner?.submission.isSameRequest(as: context) == true
			},
			isGitTurnBaselineBindingCurrent:
			{
				[weak self] operation in
				guard let self, !self.isShutdown,
						operation.context.belongsTo(
						workspace: self.model.identity,
						generation: self.model.connection.generation
						),
						let binding = self.model.execution.gitTurnBaselineBindings[
						operation.reference.identity.threadID
						]
				else
				{
					return false
				}
				return binding.context.isSameRequest(as: operation.context)
					&& binding.turnID == operation.turnID && binding.result == nil
			},
			storage: storage,
			reviewMarkerStore: reviewMarkerStore,
			taskWorkspace: taskWorkspace,
			taskWorkspaceManager: taskWorkspaceManager,
			persistence: persistence,
			projectContextStore: projectContextStore,
			completedRequestLimit: completedRequestLimit,
			usageRuntime: usageRuntime,
			previewPreparer: self.factoryDependencies.previewPreparer,
			captureConversationRead:
			{
				[weak self] followUp in
				self?.inputs.captureConversationRead(followUp)
			},
			mapEvent: mapEvent,
			deliver:
			{
				[weak self] action, afterReduction in
				self?.enqueue(
					action,
					afterReduction: afterReduction
				)
			}
		)
		preferenceStorage = storage
		if let storage
		{
			preferenceObserver = storage.observePreferences
			{
				[weak self] value in self?.dispatch(.preferences(.restored(value)))
			}
		}
	}

	var runningOperationCount: Int
	{
		runner.runningOperationCount
	}

	var retainedOperationCount: Int
	{
		runner.retainedOperationCount
	}

	/// Identity capture is an input boundary; reducers never generate identifiers.
	func operationContext(threadID: String? = nil) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: makeRequestID(),
			threadID: threadID
		)
	}

	func operation(for context: OperationContext) -> WorkspaceOperationHandle?
	{
		runner.operation(for: context)
	}

	/// Reentrant callbacks append actions; every reducer sees each action before publication.
	func dispatch(_ action: WorkspaceAction)
	{
		enqueue(
			action,
			afterReduction:
			{
			}
		)
	}

	private func enqueue(
		_ action: WorkspaceAction,
		afterReduction: @escaping () -> Void
	)
	{
		guard !isShutdown
		else
		{
			return
		}
		queuedActions.append(QueuedAction(
			action: action,
			afterReduction: afterReduction
		))
		guard !isDraining
		else
		{
			return
		}
		isDraining = true
		defer
		{
			isDraining = false
		}
		var index = 0
		while index < queuedActions.count, !isShutdown
		{
			let next = queuedActions[index]
			index += 1
			guard WorkspaceLifecycleReducer.accepts(
				next.action,
				model: model
			)
			else
			{
				next.afterReduction()
				continue
			}
			var reduction = reduceAction(next.action)
			reduceDomainEvents(in: &reduction)
			runner.reserve(
				reduction.effects,
				workspace: model.identity,
				managedWorkspace: model.lifecycle.managedWorkspace
			)
			publish(
				events: reduction.domainEvents,
				commands: reduction.presentationCommands,
				action: next.action
			)
			guard !isShutdown
			else
			{
				break
			}
			runner.accept(
				reduction.effects,
				workspace: model.identity,
				managedWorkspace: model.lifecycle.managedWorkspace
			)
			next.afterReduction()
		}
		queuedActions.removeAll(keepingCapacity: true)
	}

	private func reduceAction(_ action: WorkspaceAction) -> WorkspaceReduction
	{
		var accumulated = WorkspaceReduction()
		for reducer in reducers
		{
			let reduction = reducer.reduce(
				&model,
				action
			)
			accumulated.effects.append(contentsOf: reduction.effects)
			accumulated.domainEvents.append(contentsOf: reduction.domainEvents)
			accumulated.presentationCommands.append(contentsOf: reduction.presentationCommands)
		}
		return accumulated
	}

	private func reduceDomainEvents(in accumulated: inout WorkspaceReduction)
	{
		// Accepted domain observations finish value reduction before callbacks.
		var domainEventIndex = 0
		while domainEventIndex < accumulated.domainEvents.count
		{
			let event = accumulated.domainEvents[domainEventIndex]
			domainEventIndex += 1
			let reduction = reduceDomainEvent(
				&model,
				event
			)
			accumulated.effects.append(contentsOf: reduction.effects)
			accumulated.domainEvents.append(contentsOf: reduction.domainEvents)
			accumulated.presentationCommands.append(contentsOf: reduction.presentationCommands)
			let semanticContext = operationContext(threadID: WorkspaceSelectors(
				model: model,
				now: now()
			).selectedThreadID)
			let lifecycle = WorkspaceLifecycleComposition.reduceDomainEvent(
				&model,
				event,
				context: semanticContext
			)
			accumulated.effects.append(contentsOf: lifecycle.effects)
			accumulated.domainEvents.append(contentsOf: lifecycle.domainEvents)
			accumulated.presentationCommands.append(contentsOf: lifecycle.presentationCommands)
		}
	}

	@discardableResult
	func observe(_ observer: @escaping (WorkspaceModel) -> Void) -> UUID
	{
		let id = UUID()
		guard !isShutdown
		else
		{
			return id
		}
		observers[id] = observer
		observerOrder.append(id)
		observer(model)
		return id
	}

	func removeObserver(_ id: UUID)
	{
		observers.removeValue(forKey: id)
		observerOrder.removeAll
		{
			$0 == id
		}
	}

	func shutdown()
	{
		guard !isShutdown
		else
		{
			return
		}
		publicationObservers.removeAll()
		observers.removeAll()
		observerOrder.removeAll()
		dispatch(.workspaceLifecycle(.shutdownRequested))
		isShutdown = true
		if let preferenceObserver
		{
			preferenceStorage?.removePreferenceObserver(preferenceObserver)
		}
		publicationObservers.removeAll()
		observers.removeAll()
		observerOrder.removeAll()
		runner.shutdown()
	}

	private func publish(
		events: [WorkspaceDomainEvent],
		commands: [WorkspacePresentationCommand],
		action: WorkspaceAction
	)
	{
		let snapshot = model
		let publication = WorkspacePublication(
			model: snapshot,
			coalescible: shouldCoalescePublication(
				events: events,
				commands: commands,
				action: action
			),
			commands: commands
		)
		for observer in Array(publicationObservers.values)
		{
			observer(publication)
		}
		for id in observerOrder
		{
			guard !isShutdown
			else
			{
				return
			}
			observers[id]?(snapshot)
		}
	}

	private func shouldCoalescePublication(
		events: [WorkspaceDomainEvent],
		commands: [WorkspacePresentationCommand],
		action: WorkspaceAction
	) -> Bool
	{
		var coalescible = false
		switch action
		{
		case .workspaceLifecycle(.reusableReferencesReceived),
				.conversations(.turnReferencesRequested), .conversations(.turnReferencesReceived):
			// Internal metadata follows the pending batch instead of flushing text deltas.
			coalescible = true
		default: break
		}
		for event in events
		{
			switch event
			{
			case .backendObserved(
				let event,
				_
			):
				switch event
				{
				case .itemStarted, .itemCompleted, .agentMessageDelta,
						.commandOutputDelta, .fileChangeUpdated,
						.diffUpdated:
					coalescible = true
				default:
					break
				}
			default:
				break
			}
		}
		if !commands.isEmpty
		{
			coalescible = false
		}
		return coalescible
	}
}

struct WorkspacePersistenceBarrierError: LocalizedError
{
	let message: String
	var errorDescription: String?
	{
		message
	}
}
