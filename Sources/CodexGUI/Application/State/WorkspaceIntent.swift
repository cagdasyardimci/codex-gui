import Foundation

/// View proposals are captured with the rendered owner; reducers still decide admission.
enum WorkspaceIntent
{
	case editDraft(String), attachContext(ComposerContextItem), removeContext(String),
			reuseReference(String)
	case send, steer(String), stop
	case respond(
		PendingInteraction,
		InteractionResponse
	)
	case newChat, newChatInProject(URL), openProject(URL), selectThread(String), refreshThreads
	case setArchived(Bool), renameThread(String), archiveThread
	case archiveTask(String), deleteTask(String)
	case selectModel(String?), selectEffort(String?), selectApprovalMode(ApprovalMode),
			setFastMode(Bool)
	case toggleProjectPin(URL), renameProject(
		URL,
		String
	), signIn, reconnect
	case updateProjectContext(ProjectContext), insertPrompt(String),
			toggleBookmark(ConversationBookmark)
	case jumpBookmark(ConversationBookmark), jumpTarget(ConversationJumpTarget),
			jumpHit(MessageSearchHit)
	case search(String), loadMoreSearch, acknowledgeJump, loadEarlierTurns
	case selectReview(String), setReviewed(
		Bool,
		ReviewReference
	)
	case prepareChangeRequest(
		ReviewRequestKind,
		ReviewReference
	)
	case selectWorkspace(UUID?), createTask(String), removeWorkspace(UUID), cancelCreation(UUID)

	fileprivate var scope: Scope
	{
		switch self
		{
		case .editDraft, .attachContext, .removeContext, .reuseReference, .send, .steer,
				.insertPrompt, .prepareChangeRequest, .createTask, .renameProject, .newChat,
				.newChatInProject, .selectModel, .selectEffort, .selectApprovalMode,
				.setFastMode: return .draft
		case .renameThread, .archiveThread, .loadEarlierTurns, .selectReview,
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
		case .send: operation = inputs.send()
		case .steer(let text): inputs.steer(text)
		case .stop:
			guard store.model.execution.agentOutcome == nil,
					store.model.execution.owner == executionOwner,
					store.model.execution.submissionRequest?.requestID == submissionRequestID
			else
			{
				return false
			}
			operation = inputs.stop()
		case .respond(
			let interaction,
			let response
		):
			guard store.model.execution.agentOutcome == nil,
					let capturedSubmissionID = executionOwner?.submission.requestID,
					store.model.execution.owner?.submission.requestID == capturedSubmissionID,
					store.model.execution.pendingInteractions.contains(where:
					{
						$0.id == interaction.id && $0.threadId == interaction.threadId && $0
							.turnId == interaction.turnId && $0.itemId == interaction.itemId && $0
							.approvalId == interaction.approvalId
					})
			else
			{
				return false
			}
			operation = inputs.respond(
				to: interaction,
				with: response
			)
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
			}; await inputs.connect()
		}
		case .updateProjectContext(let context): inputs.updateProjectContext(context)
		case .insertPrompt(let id): inputs.insertSavedPrompt(id: id)
		case .toggleBookmark(let bookmark): inputs.toggleBookmark(bookmark)
		case .jumpBookmark(let bookmark): inputs.jumpToBookmark(bookmark)
		case .jumpTarget(let target): inputs.jumpToNavigationTarget(target)
		case .jumpHit(let hit): inputs.jumpToSearchHit(hit)
		case .search(let query): inputs.searchMessages(query)
		case .loadMoreSearch: inputs.loadMoreSearchHistory()
		case .acknowledgeJump: inputs.acknowledgeJump()
		case .loadEarlierTurns: inputs.loadEarlierTurns()
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
					}; await coordinator.selectWorkspace(id)
				}
			}
			else
			{
				coordinator.selectSourceCheckout()
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
				}; await coordinator.createTask(named: name)
			}
		case .removeWorkspace(let id), .cancelCreation(let id):
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

/// Account and execution chrome do not need transcript or composer values.
struct WorkspaceStatusPresentation: Equatable
{
	let executionState: ExecutionState
	let accountDescription: String
	let backendDescription: String
	let usage: UsagePresentation
	init(
		_ snapshot: ConversationSnapshot,
		ownerIdentity: String? = nil
	)
	{
		executionState = snapshot.activeExecutionState ?? snapshot.executionState
		accountDescription = snapshot.accountDescription
		backendDescription = snapshot.backendDescription
		usage = UsagePresentation(
			snapshot,
			ownerIdentity: ownerIdentity
		)
	}
}
