import Foundation

/// Each runner uses its checkout/session's dedicated CodexService connection.
/// Persistence scheduling can be shared; backend callback ownership cannot be shared.
@MainActor
final class WorkspaceEffectRunner
{
	// Internal implementation members are shared by the responsibility extensions.
	// Operation identity and group lifetime remain coordinated by this runtime.

	enum Purpose: Hashable
	{
		case connection, version, selection, account, preparation, submission, draft, interruption,
				steering, recovery, completedHistory, adoption, acknowledgement
		case reviewRead(
			ConversationKey,
			String,
			Int,
			Int,
			[ReviewMarkerIdentity]
		)
		case reviewWrite(
			ReviewMarkerIdentity,
			Int
		)
		case models, signIn, preference
		case release(UUID)
		case history(
			ConversationReadPurpose,
			String?
		)
		case page(
			String?,
			String
		)
		case turnReferences(
			String?,
			String?
		)
		case previewExpiry
		case turnContents(
			String?,
			String,
			Bool,
			Bool
		)
		case contextLoad(Int), contextSave(Int), skills(Int)
		case messageSearch(
			Int,
			String
		)
		case list, management, selectionPersistence
		case composerCommand
		case response(String)
		case sourceStartup, inputPreparation, unsentRelease, preferenceRestoration
		case composerHydration(String?), diagnostics, reusable(
			ConversationKey,
			Int,
			[String]
		)
		case usage(Int)
		case gitTurnBaselineBinding(String)
		case gitTurnBaselineDiscard(UUID)
	}

	struct RequestKey: Hashable
	{
		let workspace: WorkspaceIdentity
		let generation: Int
		let requestID: UUID

		init(_ context: OperationContext)
		{
			workspace = context.workspace
			generation = context.generation
			requestID = context.requestID
		}
	}

	struct EffectKey: Hashable
	{
		let request: RequestKey
		let purpose: Purpose
	}

	struct PendingEffect
	{
		let task: Task<Void, Never>
		let effect: WorkspaceEffect
		let handle: WorkspaceOperationHandle
		var hasStartedResponse = false
		var promotedTurnRead: ConversationTurnReadOperation? = nil
	}

	struct ReservedComposerCommand
	{
		let effect: WorkspaceEffect
		let handle: WorkspaceOperationHandle
		var isCancelled = false
	}

	let usageRuntime: UsageRuntime
	var usageDeadlineTask: Task<Void, Never>?
	var usageDeadline: UsageDeadlineOperation?
	let service: any CodexService
	let previewPreparer: any ConversationPreviewPreparing
	let captureConversationRead: (ConversationReadFollowUp) -> Void
	let gitTurnBaselineService: any GitTurnBaselineService
	let isSubmissionCurrent: (OperationContext) -> Bool
	let isSubmissionStopped: (OperationContext) -> Bool
	let isGitTurnBaselineBindingCurrent: (GitTurnBaselineBindingOperation) -> Bool
	let storage: LocalStorage?
	let reviewMarkerStore: ReviewMarkerStore?
	var reservedReviewResults: [EffectKey: WorkspaceAction] = [:]
	let taskWorkspaceManager: GitWorktreeManager?
	var retainedContexts: [UUID: UUID] = [:]
	var retainedSubmissions: [UUID: ComposerSubmission] = [:]
	var preparedThreadIDs: [UUID: String] = [:]
	var reservedPersistence: [EffectKey: Task<Void, Error>] = [:]
	var durableReferences: Set<UUID> = []
	let projectContextStore: ProjectContextStore
	var reservedContextLoads: [EffectKey: Task<ProjectContext, Error>] = [:]
	var contextPersistencePaths: Set<String> = []
	let persistence: WorkspacePersistenceScheduler
	let deliver: (WorkspaceAction, @escaping () -> Void) -> Void
	private let mapEvent: (OperationContext, AppServerEvent) -> [WorkspaceAction]
	var tasks: [EffectKey: PendingEffect] = [:]
	var reservedComposerCommands: [EffectKey: ReservedComposerCommand] = [:]
	var accepted: Set<EffectKey> = []
	var handles: [RequestKey: WorkspaceOperationHandle] = [:]
	private var completedRequests: [RequestKey] = []
	private let completedRequestLimit: Int
	var subscription: OperationContext?
	var hasObservedSubscription = false
	var isShutdown = false

	init(
		service: any CodexService,
		gitTurnBaselineService: any GitTurnBaselineService = LocalGitTurnBaselineService.shared,
		isSubmissionCurrent: @escaping (OperationContext) -> Bool =
		{
			_ in true
		},
		isSubmissionStopped: @escaping (OperationContext) -> Bool =
		{
			_ in false
		},
		isGitTurnBaselineBindingCurrent: @escaping (GitTurnBaselineBindingOperation) -> Bool =
		{
			_ in true
		},
		storage: LocalStorage? = nil,
		reviewMarkerStore: ReviewMarkerStore? = nil,
		taskWorkspace: TaskWorkspace? = nil,
		taskWorkspaceManager: GitWorktreeManager? = nil,
		persistence: WorkspacePersistenceScheduler,
		projectContextStore: ProjectContextStore = ProjectContextStore(),
		completedRequestLimit: Int = 128,
		usageRuntime: UsageRuntime = UsageRuntime(),
		previewPreparer: any ConversationPreviewPreparing = ConversationTextPreviewPreparer(),
		captureConversationRead: @escaping (ConversationReadFollowUp) -> Void =
		{
			_ in
		},
		mapEvent: @escaping (
			OperationContext,
			AppServerEvent
		) -> [WorkspaceAction],
		deliver: @escaping (
			WorkspaceAction,
			@escaping () -> Void
		) -> Void
	)
	{
		self.service = service
		self.previewPreparer = previewPreparer
		self.captureConversationRead = captureConversationRead
		self.gitTurnBaselineService = gitTurnBaselineService
		self.isSubmissionCurrent = isSubmissionCurrent
		self.isSubmissionStopped = isSubmissionStopped
		self.isGitTurnBaselineBindingCurrent = isGitTurnBaselineBindingCurrent
		self.usageRuntime = usageRuntime
		self.storage = storage
		self.reviewMarkerStore = reviewMarkerStore
		self.taskWorkspaceManager = taskWorkspaceManager
		self.persistence = persistence
		self.projectContextStore = projectContextStore
		self.completedRequestLimit = max(
			0,
			completedRequestLimit
		)
		self.mapEvent = mapEvent
		self.deliver = deliver
	}

	var runningOperationCount: Int
	{
		tasks.count + reservedComposerCommands.values.filter
		{
			!$0.isCancelled
		}.count
	}

	var retainedOperationCount: Int
	{
		handles.count
	}

	/// Captures registered effects, including preview expiry, but not the independent usage timer.
	/// Callers must select a request when unrelated effects should not delay readiness.
	func executionTasks() -> [Task<Void, Never>]
	{
		tasks.values.map(\.task)
	}

	/// Operation cancellation retires its handle before a suspended service necessarily returns.
	/// A task snapshot can also await that execution's return without changing its cancellation.
	func executionTasks(for context: OperationContext) -> [Task<Void, Never>]
	{
		let request = RequestKey(context)
		var captured = tasks.compactMap
		{
			key, pending in
			key.request == request ? pending.task : nil
		}
		if let deadline = usageDeadline, RequestKey(deadline.read.context) == request,
			let task = usageDeadlineTask
		{
			captured.append(task)
		}
		return captured
	}

	func operation(for context: OperationContext) -> WorkspaceOperationHandle?
	{
		handles[RequestKey(context)]
	}

	func shutdown()
	{
		guard !isShutdown
		else
		{
			return
		}
		isShutdown = true
		usageDeadlineTask?.cancel()
		usageDeadlineTask = nil
		usageDeadline = nil
		for submission in Array(retainedSubmissions.values)
		{
			finalizeReservationOnShutdown(submission)
		}
		retainedContexts.removeAll()
		retainedSubmissions.removeAll()
		preparedThreadIDs.removeAll()
		reservedPersistence.removeAll()
		reservedContextLoads.removeAll()
		reservedReviewResults.removeAll()
		durableReferences.removeAll()
		detachSubscription()
		let pending = tasks.values
		tasks.removeAll()
		for operation in pending
		{
			operation.task.cancel()
			operation.handle.finishedEffect(.cancelled)
		}
		for handle in handles.values
		{
			handle.cancelRemainingEffects()
		}
		reservedComposerCommands.removeAll()
		accepted.removeAll()
		handles.removeAll()
		completedRequests.removeAll()
	}

	func identity(of effect: WorkspaceEffect) -> (OperationContext, Purpose)?
	{
		switch effect
		{
		case .readReviewMarkers(let operation): return (operation.context, .reviewRead(
				operation.conversation,
				operation.turnID,
				operation.sourceRevision,
				operation.markerRevision,
				operation.identities
			))
		case .writeReviewMarker(let operation): return (
				operation.context,
				.reviewWrite(
					operation.identity,
					operation.markerRevision
				)
			)
		case .respond(let operation): return (operation.context, .response(operation.interactionID))
		case .interrupt(let operation): return (operation.context, .interruption)
		case .steer(let operation): return (operation.context, .steering)
		case .readRecovery(let operation): return (operation.context, .recovery)
		case .readCompletedHistory(let operation): return (operation.context, .completedHistory)
		case .persistPreparedConversation(let write): return (
				write.prepared.submission.context,
				.adoption
			)
		case .acknowledgeSubmission(let write): return (write.submission.context, .acknowledgement)
		case .releaseSubmission(let operation): return (
				operation.context,
				.release(operation.submission.context.requestID)
			)
		case .validateComposerInput(let operation): return (operation.context, .inputPreparation)
		case .releaseUnsentSubmission(let submission): return (submission.context, .unsentRelease)
		case .restoreSourceStartup(let context): return (context, .sourceStartup)
		case .restorePreferences(let context): return (context, .preferenceRestoration)
		case .restoreComposer(let context): return (context, .composerHydration(context.threadID))
		case .readBackendDiagnostics(let context): return (context, .diagnostics)
		case .validateReusableReferences(let operation): return (
				operation.context,
				.reusable(
					operation.conversation,
					operation.revision,
					operation.items.map
					{
						[$0.id, $0.path ?? "", $0.excerpt ?? ""].joined(separator: "\u{0}")
					}
				)
			)
		case .connect(let context): return (context, .connection)
		case .readExecutableVersion(let context): return (context, .version)
		case .readSelection(let context): return (context, .selection)
		case .readConversationHistory(let operation): return (
				operation.context,
				.history(
					operation.purpose,
					operation.context.threadID
				)
			)
		case .readConversationPage(let operation): return (
				operation.context,
				.page(
					operation.context.threadID,
					operation.pageScope.cursor
				)
			)
		case .readTurnReferences(let operation): return (
				operation.context,
				.turnReferences(
					operation.context.threadID,
					operation.cursor
				)
			)
		case .expireTurnPreviews(let context): return (context, .previewExpiry)
		case .readTurnContents(let operation): return (
				operation.context,
				.turnContents(
					operation.context.threadID,
					operation.reference.id,
					operation.isPreview,
					operation.isWindow
				)
			)
		case .readConversationList(let operation): return (operation.context, .list)
		case .forkConversation(let request): return (request.context, .composerCommand)
		case .compactConversation(let operation), .startConversationReview(let operation):
			return (operation.request.context, .composerCommand)
		case .updateCommandSettings(let operation):
			return (operation.request.context, .composerCommand)
		case .archiveProjectChats(let operation): return (operation.context, .management)
		case .manageConversation(let operation): return (managementContext(operation), .management)
		case .persistConversationSelection(
			let context,
			_
		): return (context, .selectionPersistence)
		case .readAccount(let context): return (context, .account)
		case .loadProjectContext(let operation): return (
				operation.context,
				.contextLoad(operation.revision)
			)
		case .saveProjectContext(let operation): return (
				operation.context,
				.contextSave(operation.revision)
			)
		case .readSkills(let operation): return (operation.context, .skills(operation.attempt))
		case .searchMessages(
			let operation,
			_,
			_
		):
			return (operation.context, .messageSearch(
				operation.historyRevision,
				operation.query
			))
		case .readModels(let context): return (context, .models)
		case .beginSignIn(let context): return (context, .signIn)
		case .persistPreference(let write): return (write.context, .preference)
		case .readUsage(let operation): return (operation.context, .usage(operation.attempt))
		case .prepareSubmission(let submission): return (submission.context, .preparation)
		case .startSubmission(let prepared): return (prepared.submission.context, .submission)
		case .bindGitTurnBaseline(let operation):
			return (operation.context, .gitTurnBaselineBinding(operation.turnID))
		case .discardGitTurnBaseline(let operation):
			return (operation.context, .gitTurnBaselineDiscard(operation.reference.identity.id))
		case .persistDraft(let write): return (write.context, .draft)
		default: return nil
		}
	}

	func beginSynchronous(
		_ effect: WorkspaceEffect,
		context: OperationContext
	) -> WorkspaceOperationHandle?
	{
		guard let (_, purpose) = identity(of: effect)
		else
		{
			return nil
		}
		let request = RequestKey(context)
		guard accepted.insert(EffectKey(
			request: request,
			purpose: purpose
		)).inserted
		else
		{
			return nil
		}
		let previous = handles[request]
		let handle = previous?.completion == nil
			? (previous ?? WorkspaceOperationHandle(context: context))
			: WorkspaceOperationHandle(context: context)
		if previous?.completion != nil
		{
			completedRequests.removeAll
			{
				$0 == request
			}
		}
		handles[request] = handle
		handle.acceptedEffect()
		return handle
	}

	func completeSynchronous(
		_ action: WorkspaceAction,
		context: OperationContext,
		handle: WorkspaceOperationHandle,
		completion: WorkspaceOperationCompletion
	)
	{
		deliver(action)
		{
			handle.finishedEffect(completion)
			self.retireCompletedRequest(RequestKey(context))
		}
	}

	func start(
		_ effect: WorkspaceEffect,
		context: OperationContext,
		purpose: Purpose,
		managedWorkspace: TaskWorkspace?
	)
	{
		if case .expireTurnPreviews = effect
		{
			let oldTimers = tasks.keys.filter
			{
				$0.purpose == .previewExpiry
			}
			for key in oldTimers
			{
				if let old = tasks[key], case .expireTurnPreviews(let context) = old.effect
				{
					cancel(context)
				}
			}
		}
		if case .readTurnContents(let incoming) = effect
		{
			cancelSupersededTurnReads(incoming)
		}
		let request = RequestKey(context)
		let key = EffectKey(
			request: request,
			purpose: purpose
		)
		reserve(
			[effect],
			workspace: context.workspace
		)
		let reservedCommand = reservedComposerCommands.removeValue(forKey: key)
		if let reservedCommand
		{
			guard !reservedCommand.isCancelled, reservedCommand.handle.completion == nil
			else
			{
				return
			}
		}
		else
		{
			guard acceptEffectKey(key)
			else
			{
				return
			}
		}
		let transportContinuation = handles.first
		{
			$0.key.workspace.sessionID == request.workspace.sessionID
				&& $0.key.generation == request.generation && $0.key.requestID == request.requestID
				&& $0.value.completion == nil
				&& accepted.contains(EffectKey(
					request: $0.key,
					purpose: .version
				))
		}.map(\.value)
		let previous = reservedCommand?.handle ?? handles[request] ?? transportContinuation
		if previous?.completion != nil
		{
			completedRequests.removeAll
			{
				$0 == request
			}
		}
		let handle = previous?.completion == nil
			? (previous ?? WorkspaceOperationHandle(context: context))
			: WorkspaceOperationHandle(context: context)
		handles[request] = handle
		if reservedCommand == nil
		{
			handle.acceptedEffect()
		}
		let persistenceTask = reservedPersistence.removeValue(forKey: key)
		let contextLoadTask = reservedContextLoads.removeValue(forKey: key)

		let task = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let action: WorkspaceAction
			let completion: WorkspaceOperationCompletion
			do
			{
				action = try await self.perform(
					effect,
					context: context,
					persistenceTask: persistenceTask,
					contextLoadTask: contextLoadTask,
					managedWorkspace: managedWorkspace
				)
				completion = .finished
			}
			catch
			{
				if let startFailure = error as? SubmissionStartFailure
				{
					action = .execution(.submissionStartFailed(
						context,
						startFailure.failure,
						startFailure.pendingCapture
					))
					completion = .failed(startFailure.failure)
				}
				else
				{
					let failure = self.failure(
						for: effect,
						error: error
					)
					action = self.failureAction(
						for: effect,
						context: context,
						failure: failure
					)
					completion = .failed(failure)
				}
			}
			// Cancellation retires the local task even if a service ignores Task cancellation.
			guard !Task.isCancelled, self.tasks[key] != nil
			else
			{
				return
			}
			self.tasks.removeValue(forKey: key)
			self.deliver(action)
			{
				// Chained effects are accepted before the completed effect leaves the group.
				handle.finishedEffect(completion)
				self.retireCompletedRequest(request)
			}
		}
		tasks[key] = PendingEffect(
			task: task,
			effect: effect,
			handle: handle
		)
	}

	/// History refreshes share a captured search request. Its latest revision also
	/// rejects older replay without retaining every completed history revision.
	private func acceptEffectKey(_ key: EffectKey) -> Bool
	{
		guard case .messageSearch(
			let revision,
			_
		) = key.purpose
		else
		{
			return accepted.insert(key).inserted
		}
		var superseded: [EffectKey] = []
		for previous in accepted where previous.request == key.request
		{
			guard case .messageSearch(
				let previousRevision,
				_
			) = previous.purpose
			else
			{
				continue
			}
			guard previousRevision <= revision
			else
			{
				return false
			}
			if previousRevision < revision
			{
				superseded.append(previous)
			}
		}
		guard accepted.insert(key).inserted
		else
		{
			return false
		}
		accepted.subtract(superseded)
		return true
	}

	private func managementContext(_ operation: ThreadManagementOperation) -> OperationContext
	{
		switch operation
		{
		case .rename(
			let context,
			_
		), .archive(let context), .unarchive(let context), .delete(let context): return context
		}
	}

	func scheduleUsageDeadline(_ operation: UsageDeadlineOperation)
	{
		usageDeadlineTask?.cancel()
		usageDeadline = operation
		usageDeadlineTask = Task
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			do
			{
				try await self.usageRuntime.waitUntil(operation.deadline)
			}
			catch
			{
				return
			}
			guard !Task.isCancelled, !self.isShutdown, self.usageDeadline == operation
			else
			{
				return
			}
			self.usageDeadlineTask = nil
			self.usageDeadline = nil
			self.deliver(.usage(.freshnessDeadlineElapsed(
				operation,
				now: self.usageRuntime.now()
			)))
			{
			}
		}
	}

	func cancel(
		_ context: OperationContext,
		purpose: Purpose? = nil
	)
	{
		let request = RequestKey(context)
		let reservedKeys = reservedComposerCommands.keys.filter
		{
			$0.request == request && (purpose == nil || $0.purpose == purpose)
		}
		for key in reservedKeys
		{
			guard var reserved = reservedComposerCommands[key], !reserved.isCancelled
			else
			{
				continue
			}
			// Keep cancellation until start consumes it, even if replay history expires.
			reserved.isCancelled = true
			reservedComposerCommands[key] = reserved
			let failure = failure(
				for: reserved.effect,
				message: "Local operation cancelled; no remote outcome is established."
			)
			deliver(failureAction(
				for: reserved.effect,
				context: reserved.handle.context,
				failure: failure
			))
			{
				reserved.handle.finishedEffect(.cancelled)
				self.retireCompletedRequest(request)
			}
		}
		let keys = tasks.keys.filter
		{
			let ownsPromotion = tasks[$0]?.promotedTurnRead?.context
				.isSameRequest(as: context) == true
			return ($0.request == request || ownsPromotion) &&
				(purpose == nil || $0.purpose == purpose)
		}
		for key in keys
		{
			guard let pending = tasks.removeValue(forKey: key)
			else
			{
				continue
			}
			pending.task.cancel()
			let failure = failure(
				forCancelled: pending,
				context: context
			)
			deliver(failureAction(
				for: pending.effect,
				context: pending.handle.context,
				failure: failure
			))
			{
				pending.handle.finishedEffect(.cancelled)
				self.retireCompletedRequest(key.request)
			}
		}
	}

	/// Command operation handles must exist before pending command state reaches observers.
	func reserveComposerCommand(
		_ effect: WorkspaceEffect,
		context: OperationContext,
		key: EffectKey
	)
	{
		guard reservedComposerCommands[key] == nil, accepted.insert(key).inserted
		else
		{
			return
		}
		let previous = handles[key.request]
		if previous?.completion != nil
		{
			completedRequests.removeAll
			{
				$0 == key.request
			}
		}
		let handle = previous?.completion == nil
			? (previous ?? WorkspaceOperationHandle(context: context))
			: WorkspaceOperationHandle(context: context)
		handles[key.request] = handle
		handle.acceptedEffect()
		reservedComposerCommands[key] = ReservedComposerCommand(
			effect: effect,
			handle: handle
		)
	}

	/// Recently completed requests deduplicate replay; callers own their returned handles.
	/// Active groups are never evicted, and completion bookkeeping has a fixed bound.
	private func retireCompletedRequest(_ request: RequestKey)
	{
		guard handles[request]?.completion != nil,
				!completedRequests.contains(request)
		else
		{
			return
		}
		completedRequests.append(request)
		while completedRequests.count > completedRequestLimit
		{
			let expired = completedRequests.removeFirst()
			handles.removeValue(forKey: expired)
			accepted = accepted.filter
			{
				$0.request != expired
			}
		}
	}

	func attachSubscription(_ context: OperationContext)
	{
		subscription = context
		hasObservedSubscription = true
		service.onEvent =
		{
			[weak self] event in
			guard let self, self.subscription == context, !self.isShutdown
			else
			{
				return
			}
			// Event freshness belongs to purpose-specific reducers, not request-ID filtering here.
			for action in self.mapEvent(
				context,
				event
			)
			{
				self.deliver(
					action,
					{
					}
				)
			}
		}
		service.onDisconnect =
		{
			[weak self] message in
			guard let self, self.subscription == context, !self.isShutdown
			else
			{
				return
			}
			self.deliver(
				.connection(.disconnected(
					workspace: context.workspace,
					generation: context.generation,
					message: message
				)),
				{
				}
			)
		}
	}

	func detachSubscription()
	{
		guard subscription != nil
		else
		{
			return
		}
		subscription = nil
		service.onEvent = nil
		service.onDisconnect = nil
	}
}
