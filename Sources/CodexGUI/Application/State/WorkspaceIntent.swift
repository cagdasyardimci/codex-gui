import Foundation

/// View proposals are captured with the rendered owner; reducers still decide admission.
enum WorkspaceIntent
{
	case editDraft(String)
	case attachContext(ComposerContextItem)
	case removeContext(String)
	case reuseReference(String)
	case send
	case steer(String)
	case stop
	case slashCommand(SlashCommandInvocation)
	case acknowledgeSlashCommand(SlashCommandPresentationRequest)
	case completeSlashCommand(
		SlashCommandPresentationRequest,
		SlashCommandInvocation
	)
	case recoverFork(
		SlashCommandPresentationRequest,
		ForkRecoveryChoice
	)
	case retryPlanSettings(
		SlashCommandPresentationRequest,
		CollaborationModeKind
	)
	case respond(
		PendingInteraction,
		InteractionResponse
	)

	case newChat
	case newChatInProject(URL)
	case openProject(URL)
	case selectThread(String)
	case refreshThreads
	case setArchived(Bool)
	case renameThread(String)
	case archiveThread
	case archiveTask(String)
	case deleteTask(String)

	case selectModel(String?)
	case selectEffort(String?)
	case selectApprovalMode(ApprovalMode)
	case setFastMode(Bool)
	case toggleProjectPin(URL)
	case renameProject(
		URL,
		String
	)
	case signIn
	case reconnect

	case updateProjectContext(ProjectContext)
	case insertPrompt(String)
	case toggleBookmark(ConversationBookmark)
	case jumpBookmark(ConversationBookmark)
	case jumpTarget(ConversationJumpTarget)
	case jumpHit(MessageSearchHit)
	case search(String)
	case dismissSearch
	case loadMoreSearch
	case acknowledgeJump
	case loadEarlierTurns
	case loadEarlierTurnReferences
	case loadTurnPreview(String)
	case updateConversationViewport(ConversationViewport)

	case selectReview(String)
	case setReviewed(
		Bool,
		ReviewReference
	)
	case prepareChangeRequest(
		ReviewRequestKind,
		ReviewReference
	)

	case selectWorkspace(UUID?)
	case createTask(String)
	case removeWorkspace(UUID)
	case cancelCreation(UUID)

	fileprivate var scope: Scope
	{
		switch self
		{
		case .slashCommand, .acknowledgeSlashCommand, .completeSlashCommand, .retryPlanSettings,
				.recoverFork,
				.editDraft, .attachContext, .removeContext, .reuseReference, .send, .steer,
				.insertPrompt, .prepareChangeRequest, .createTask, .renameProject, .newChat,
				.newChatInProject, .selectModel, .selectEffort, .selectApprovalMode,
				.setFastMode: return .draft
		case .renameThread, .archiveThread, .loadEarlierTurns, .loadEarlierTurnReferences,
				.loadTurnPreview, .updateConversationViewport,
				.selectReview,
				.setReviewed, .toggleBookmark, .acknowledgeJump: return .conversation
		default: return .owner
		}
	}
	fileprivate enum Scope: Equatable
	{
		case owner, conversation, draft
	}
}

/// This reference is a transient callback target, never a domain state owner.
@MainActor
final class WorkspaceIntentTarget
{
	let store: WorkspaceStateStore
	private(set) var operation: WorkspaceOperationHandle?
	let reference: WorkspaceLifecycleOwnerReference
	let generation: Int
	let selectionEpoch: Int
	let conversation: ConversationKey
	let draftLifetime: Int
	let activeThreadID: String?
	private weak var coordinator: TaskWorkspaceCoordinator?
	private let requiresCoordinator: Bool
	private let records: [UUID: TaskWorkspace]
	private let executionOwner: ExecutionOwner?
	private let submissionRequestID: UUID?
	var presentationIdentity: String
	{
		"\(ObjectIdentifier(store)):\(generation)"
	}

	init(
		store: WorkspaceStateStore,
		snapshot: ConversationSnapshot,
		coordinator: TaskWorkspaceCoordinator? = nil
	)
	{
		self.store = store
		self.coordinator = coordinator
		requiresCoordinator = coordinator != nil
		reference = snapshot.workspaceOwner ?? WorkspaceLifecycleReducer.reference(store.model)
		generation = store.model.connection.generation
		selectionEpoch = snapshot.workspaceSelectionEpoch
		conversation = snapshot.selectedThreadID.map(ConversationKey.thread) ?? .newChat
		draftLifetime = snapshot.composerDraftLifetime
		activeThreadID = snapshot.activeThreadID
		records = coordinator?.model.workspaces ?? [:]
		executionOwner = store.model.execution.owner
		submissionRequestID = store.model.execution.submissionRequest?.requestID
	}

	func accepts(_ intent: WorkspaceIntent) -> Bool
	{
		guard !store.model.lifecycle.isShutdown,
				WorkspaceLifecycleReducer.reference(store.model) == reference,
				store.model.connection.generation == generation
		else
		{
			return false
		}
		if requiresCoordinator
		{
			guard let coordinator, coordinator.store(for: reference) === store,
					coordinator.selectedStore === store,
					coordinator.model.selectionEpoch == selectionEpoch
			else
			{
				return false
			}
		}
		if intent.scope != .owner
		{
			guard store.model.conversations.selectedConversation == conversation
			else
			{
				return false
			}
		}
		if intent.scope == .draft
		{
			guard store.currentSnapshot.composerDraftLifetime == draftLifetime
			else
			{
				return false
			}
		}
		return true
	}

	/// The import worker retains its generated copy only after the draft accepts it.
	func attachImportedImage(_ item: ComposerContextItem) -> Bool
	{
		guard dispatch(.attachContext(item))
		else
		{
			return false
		}
		return store.model.composer.drafts[conversation]?.context.contains
		{
			$0.id == item.id && $0.path == item.path
		} == true
	}

	@discardableResult
	func dispatch(_ intent: WorkspaceIntent) -> Bool
	{
		guard accepts(intent)
		else
		{
			return false
		}
		operation = nil
		let inputs = store.inputs
		switch intent
		{
		case .editDraft(let text): inputs.updateDraft(text)
		case .attachContext(let item): inputs.addDraftContext(item)
		case .removeContext(let id): inputs.removeDraftContext(id: id)
		case .reuseReference(let id): inputs.reuseReference(id: id)
		case .slashCommand(let invocation): operation = inputs.performSlashCommand(invocation)
		case .acknowledgeSlashCommand(let request): inputs.acknowledgeSlashCommand(request)
		case .completeSlashCommand(
			let request,
			let invocation
		):
			operation = inputs.completeSlashCommand(
				request,
				invocation: invocation
			)
		case .recoverFork(
			let request,
			let choice
		):
			inputs.recoverFork(
				request,
				choice: choice
			)
		case .retryPlanSettings(
			let request,
			let mode
		):
			operation = inputs.retryPlanSettings(
				request,
				mode: mode
			)
		case .send: operation = inputs.send()
		case .steer(let text): inputs.steer(text)
		case .stop:
			guard let execution = capturedExecution,
					execution.agentOutcome == nil,
					execution.owner == executionOwner,
					execution.submissionRequest?.requestID == submissionRequestID
			else
			{
				return false
			}
			operation = inputs.stop(
				conversation: conversation,
				capturedOwner: executionOwner
			)
		case .respond(
			let interaction,
			let response
		):
			guard respondToCapturedInteraction(
				interaction,
				response: response,
				inputs: inputs
			)
			else
			{
				return false
			}
		case .newChat: inputs.newChat()
		case .newChatInProject(let url):
			if store.model.identity.canonicalCheckoutPath == url.standardizedFileURL
				.path
			{
				inputs.newChat()
			}
			else
			{
				openProject(url)
			}
		case .openProject(let url): openProject(url)
		case .selectThread(let id): operation = inputs.selectThread(id)
		case .refreshThreads: inputs.refreshThreads()
		case .setArchived(let enabled): inputs.setArchivedFilter(enabled)
		case .renameThread(let name): inputs.renameSelectedThread(name)
		case .archiveThread: inputs.archiveSelectedThread()
		case .archiveTask(let id): inputs.manageSidebarTask(
				id,
				permanentlyDelete: false
			)
		case .deleteTask(let id): inputs.manageSidebarTask(
				id,
				permanentlyDelete: true
			)
		case .selectModel(let id): inputs.selectModel(id)
		case .selectEffort(let effort): inputs.selectEffort(effort)
		case .selectApprovalMode(let mode): inputs.selectApprovalMode(mode)
		case .setFastMode(let enabled): inputs.setFastMode(enabled)
		case .toggleProjectPin(let url): inputs.toggleProjectPin(url)
		case .renameProject(
			let url,
			let name
		): inputs.renameProject(
				url,
				name: name
			)
		case .signIn: inputs.signIn()
		case .reconnect: Task
		{
			guard self.accepts(intent)
			else
			{
				return
			}
			await inputs.connect()
		}
		case .updateProjectContext(let context): inputs.updateProjectContext(context)
		case .insertPrompt(let id): inputs.insertSavedPrompt(id: id)
		case .toggleBookmark(let bookmark): inputs.toggleBookmark(bookmark)
		case .jumpBookmark(let bookmark): inputs.jumpToBookmark(bookmark)
		case .jumpTarget(let target): inputs.jumpToNavigationTarget(target)
		case .jumpHit(let hit): inputs.jumpToSearchHit(hit)
		case .search(let query): inputs.searchMessages(query)
		case .dismissSearch: inputs.dismissMessageSearch()
		case .loadMoreSearch: inputs.loadMoreSearchHistory()
		case .acknowledgeJump: inputs.acknowledgeJump()
		case .loadEarlierTurns: inputs.loadEarlierTurns()
		case .loadEarlierTurnReferences: inputs.loadEarlierTurnReferences()
		case .loadTurnPreview(let turnID): inputs.loadTurnPreview(turnID)
		case .updateConversationViewport(let viewport): inputs.updateConversationViewport(viewport)
		case .selectReview(let id): inputs.selectReviewTurn(id)
		case .setReviewed(
			let reviewed,
			let reference
		): inputs.setReviewed(
				reviewed,
				reference: reference
			)
		case .prepareChangeRequest(
			let kind,
			let reference
		): inputs.prepareChangeRequest(
				kind: kind,
				reference: reference
			)
		case .selectWorkspace(let id):
			guard selectCapturedWorkspace(
				id,
				intent: intent
			)
			else
			{
				return false
			}
		case .createTask(let name):
			guard let coordinator
			else
			{
				return false
			}
			Task
			{
				guard self.accepts(intent)
				else
				{
					return
				}
				await coordinator.createTask(named: name)
			}
		case .removeWorkspace(let id), .cancelCreation(let id):
			guard removeCapturedWorkspace(
				id,
				intent: intent
			)
			else
			{
				return false
			}
		}
		return true
	}

	private func respondToCapturedInteraction(
		_ interaction: PendingInteraction,
		response: InteractionResponse,
		inputs: WorkspaceStoreInputs
	) -> Bool
	{
		guard let execution = capturedExecution, execution.agentOutcome == nil,
				let capturedSubmissionID = executionOwner?.submission.requestID,
				execution.owner?.submission.requestID == capturedSubmissionID,
				execution.pendingInteractions.contains(where:
				{
					pendingInteraction in
					pendingInteraction.id == interaction.id
						&& pendingInteraction.threadId == interaction.threadId
						&& pendingInteraction.turnId == interaction.turnId
						&& pendingInteraction.itemId == interaction.itemId
						&& pendingInteraction.approvalId == interaction.approvalId
				})
		else
		{
			return false
		}
		operation = inputs.respond(
			to: interaction,
			with: response
		)
		return true
	}

	private var capturedExecution: ExecutionModel?
	{
		if let executionOwner
		{
			return store.model.execution(for: executionOwner.submission)
		}
		return store.model.execution(for: conversation)
	}

	private func selectCapturedWorkspace(
		_ id: UUID?,
		intent: WorkspaceIntent
	) -> Bool
	{
		guard let coordinator
		else
		{
			return false
		}
		if let id
		{
			guard records[id] == coordinator.model.workspaces[id]
			else
			{
				return false
			}
			Task
			{
				guard self.accepts(intent),
						self.records[id] == coordinator.model.workspaces[id]
				else
				{
					return
				}
				await coordinator.selectWorkspace(id)
			}
		}
		else
		{
			coordinator.selectSourceCheckout()
		}
		return true
	}

	private func removeCapturedWorkspace(
		_ id: UUID,
		intent: WorkspaceIntent
	) -> Bool
	{
		guard let coordinator, let expected = records[id],
				expected == coordinator.model.workspaces[id]
		else
		{
			return false
		}
		Task
		{
			guard self.accepts(intent),
					coordinator.model.workspaces[id] == expected
			else
			{
				return
			}
			if case .removeWorkspace = intent
			{
				await coordinator.removeCheckout(id: id)
			}
			else
			{
				await coordinator.cancelIncompleteCreation(id: id)
			}
		}
		return true
	}

	private func openProject(_ url: URL)
	{
		if let coordinator
		{
			coordinator.openProject(url)
		}
		else
		{
			store.inputs.openProject(url)
		}
	}
}
