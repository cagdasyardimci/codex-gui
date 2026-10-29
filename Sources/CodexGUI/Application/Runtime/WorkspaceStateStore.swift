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
	private var isContinuingMessageQueues = false
	private var isShutdown = false
	private var observers: [UUID: (WorkspaceModel) -> Void] = [:]
	private var observerOrder: [UUID] = []
	private var runner: WorkspaceEffectRunner!
	private weak var preferenceStorage: LocalStorage?
	private var preferenceObserver: UUID?
	let factoryDependencies: WorkspaceStoreDependencies
	private var publicationObservers: [UUID: (WorkspacePublication) -> Void] = [:]
	private var backendEventObservers: [UUID: (AppServerEvent) -> Void] = [:]
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
		let executions = model.allExecutions
		let activeExecution = executions.first
		{
			$0.state.isBusy
		} ?? executions.first
		{
			$0.blocksCleanup
		} ?? model.execution

		return WorkspaceLifecycleObservation(
			reference: WorkspaceLifecycleReducer.reference(model),
			executionState: activeExecution.state,
			activeThreadID: activeExecution.activeThreadID,
			unresolvedCommands: executions.contains
			{
				$0.commandLifetime.hasPendingCommands
			},
			remoteOutcomeUncertain: model.hasUncertainExecutionRequest
				|| model.composerCommands.uncertainFork != nil || model.lifecycle
				.managedOwnershipConflict != nil,
			needsReconciliation: model.hasExecutionReconciliation,
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

	/// Auxiliary read-only surfaces share the subscription without taking execution ownership.
	func observeBackendEvents(_ observer: @escaping (AppServerEvent) -> Void) -> UUID
	{
		let id = UUID()
		if !isShutdown
		{
			backendEventObservers[id] = observer
		}
		return id
	}

	func removeBackendEventObserver(_ id: UUID)
	{
		backendEventObservers.removeValue(forKey: id)
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
				) && self.model.execution(for: context)?.owner?.submission
					.isSameRequest(as: context) == true
			},
			isSubmissionStopped:
			{
				[weak self] context in
				guard let self, !self.isShutdown
				else
				{
					return false
				}
				guard let execution = self.model.execution(for: context)
				else
				{
					return false
				}
				return execution.stopRequested
					&& execution.owner?.submission.isSameRequest(as: context) == true
			},
			isGitTurnBaselineBindingCurrent:
			{
				[weak self] operation in
				guard let self, !self.isShutdown,
						operation.context.belongsTo(
						workspace: self.model.identity,
						generation: self.model.connection.generation
						),
						let binding = self.model.execution(
						for: ConversationKey.thread(operation.reference.identity.threadID)
						).gitTurnBaselineBindings[
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

	/// Captures currently accepted finite execution without waiting for long-lived subscriptions.
	func executionTasks() -> [Task<Void, Never>]
	{
		runner.executionTasks()
	}

	/// Captures current execution tasks, including a usage deadline, before they are retired.
	/// Awaiting these tasks includes a canceled service's return after its handle completed.
	func executionTasks(for context: OperationContext) -> [Task<Void, Never>]
	{
		runner.executionTasks(for: context)
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
			if !isShutdown && !isContinuingMessageQueues
			{
				isContinuingMessageQueues = true
				inputs.continueMessageQueues()
				isContinuingMessageQueues = false
			}
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
			var reducedModel = model
			let reduction = WorkspaceExecutionScope.reduce(
				action: next.action,
				model: &reducedModel
			)
			{
				scopedModel in
				var result = self.reduceAction(
					next.action,
					model: &scopedModel
				)
				self.reduceDomainEvents(
					in: &result,
					model: &scopedModel
				)
				return result
			}
			model = reducedModel
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

	private func reduceAction(
		_ action: WorkspaceAction,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		var accumulated = WorkspaceReduction()
		for reducer in reducers
		{
			let reduction = reducer.reduce(
				&model,
				action
			)
			accumulated.merge(reduction)
		}
		return accumulated
	}

	private func reduceDomainEvents(
		in accumulated: inout WorkspaceReduction,
		model: inout WorkspaceModel
	)
	{
		// Accepted domain observations finish value reduction before callbacks.
		var domainEventIndex = 0
		while domainEventIndex < accumulated.domainEvents.count
		{
			let event = accumulated.domainEvents[domainEventIndex]
			domainEventIndex += 1
			let reduction = WorkspaceExecutionScope.reduce(
				event: event,
				model: &model
			)
			{
				scopedModel in
				var result = self.reduceDomainEvent(
					&scopedModel,
					event
				)
				let semanticContext = OperationContext(
					workspace: scopedModel.identity,
					generation: scopedModel.connection.generation,
					requestID: self.makeRequestID(),
					threadID: scopedModel.conversations.selectedConversation.threadID
				)
				result.merge(WorkspaceLifecycleComposition.reduceDomainEvent(
					&scopedModel,
					event,
					context: semanticContext
				))
				return result
			}
			accumulated.merge(reduction)
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
		backendEventObservers.removeAll()
		observers.removeAll()
		observerOrder.removeAll()
		dispatch(.workspaceLifecycle(.shutdownRequested))
		isShutdown = true
		if let preferenceObserver
		{
			preferenceStorage?.removePreferenceObserver(preferenceObserver)
		}
		publicationObservers.removeAll()
		backendEventObservers.removeAll()
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
		UITestEvidenceRecorder.shared.record(
			snapshot,
			action: action
		)
		if case .execution(.backendObserved(
			let context,
			let event,
			_
		)) = action,
			context.belongsTo(
				workspace: model.identity,
				generation: model.connection.generation
			)
		{
			for observer in Array(backendEventObservers.values)
			{
				observer(event)
			}
		}
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
