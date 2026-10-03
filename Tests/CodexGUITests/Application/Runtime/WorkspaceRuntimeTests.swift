import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct WorkspaceRuntimeTests
{
	@Test
	func reentrantObserversPreserveActionsAndComposedPublication()
	{
		var reduced: [String] = []
		let first = WorkspaceReducer(reduceEffects:
			{
				model, action in
				if case .preferences(.modelSelected(
					_,
					let value
				)) = action
				{
					reduced.append(value ?? "nil")
					model.preferences.selectedModelID = value
				}
				return []
			})
		let second = WorkspaceReducer(reduceEffects:
			{
				model, _ in
				model.connection.statusMessage = model.preferences.selectedModelID
				return []
			})
		let store = makeStore(reducers: [first, second])
		var published: [String] = []
		store.observe
		{
			model in
			guard let value = model.preferences.selectedModelID
			else
			{
				return
			}
			#expect(model.connection.statusMessage == value)
			published.append(value)
			if value == "first"
			{
				store.dispatch(.preferences(.modelSelected(
					store.operationContext(),
					"second"
				)))
				store.dispatch(.preferences(.modelSelected(
					store.operationContext(),
					"third"
				)))
				#expect(store.model.preferences.selectedModelID == "first")
			}
		}
		store.dispatch(.preferences(.modelSelected(
			store.operationContext(),
			"first"
		)))
		#expect(reduced == ["first", "second", "third"])
		#expect(published == reduced)
		store.shutdown()
	}

	@Test
	func obsoleteReadCannotReplaceNewSelectionAndDuplicatesExecuteOnce() async
	{
		let service = RuntimeService()
		let store = makeStore(
			service: service,
			reducers: [selectionReducer()]
		)
		let first = store.operationContext(threadID: "first")
		let second = store.operationContext(threadID: "second")
		store.dispatch(.conversations(.selectionRequested(first)))
		store.dispatch(.conversations(.selectionRequested(first)))
		await service.readStarted("first")
		#expect(service.readIDs == ["first"])
		store.dispatch(.conversations(.selectionRequested(second)))
		await service.readStarted("second")
		service.completeRead("second")
		#expect(await store.operation(for: second)?.wait() == .finished)
		#expect(store.model.conversations.threads.first?.id == "second")
		service.completeRead("first")
		#expect(await store.operation(for: first)?.wait() == .finished)
		#expect(store.model.conversations.threads.first?.id == "second")
		#expect(store.runningOperationCount == 0)
		store.shutdown()
	}

	@Test
	func cancellationSettlesHandleRejectsLateReadAndPreservesOtherStore() async
	{
		let service = RuntimeService()
		let otherService = RuntimeService()
		let store = makeStore(
			service: service,
			reducers: [selectionReducer()]
		)
		let other = makeStore(
			service: otherService,
			reducers: [selectionReducer()]
		)
		let context = store.operationContext(threadID: "first")
		let otherContext = other.operationContext(threadID: "second")
		store.dispatch(.conversations(.selectionRequested(context)))
		other.dispatch(.conversations(.selectionRequested(otherContext)))
		await service.readStarted("first")
		await otherService.readStarted("second")
		let handle = store.operation(for: context)!
		var cancellationPublished = false
		store.observe
		{
			model in
			if model.conversations.error?.contains("Local operation cancelled") == true
			{
				#expect(handle.completion == nil)
				cancellationPublished = true
			}
		}
		store.dispatch(.execution(.stopRequested(context)))
		#expect(await handle.wait() == .cancelled)
		#expect(cancellationPublished)
		#expect(store.model.conversations.error?.contains("Local operation cancelled") == true)
		#expect(store.runningOperationCount == 0)
		#expect(other.runningOperationCount == 1)
		service.completeRead("first")
		await service.readReturned("first")
		#expect(store.model.conversations.threads.isEmpty)
		otherService.completeRead("second")
		#expect(await other.operation(for: otherContext)?.wait() == .finished)
		#expect(other.model.conversations.threads.first?.id == "second")
		store.shutdown()
		other.shutdown()
	}

	@Test
	func failuresAreReducedBeforeCompletionAndForeignEffectsAreRejected() async
	{
		let service = RuntimeService()
		let store = makeStore(
			service: service,
			reducers: [selectionReducer()]
		)
		let context = store.operationContext(threadID: "first")
		store.dispatch(.conversations(.selectionRequested(context)))
		await service.readStarted("first")
		service.failRead("first")
		let completion = await store.operation(for: context)!.wait()
		if case .failed(let failure) = completion
		{
			#expect(store.model.conversations.error == failure.message)
			#expect(!failure.outcomeIsUncertain)
		}
		else
		{
			Issue.record("Expected a failed finite operation")
		}
		var foreign = context
		foreign = OperationContext(
			workspace: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: nil
			),
			generation: foreign.generation,
			requestID: UUID(),
			threadID: "foreign"
		)
		store.dispatch(.conversations(.selectionRequested(foreign)))
		#expect(store.operation(for: foreign) == nil)
		#expect(service.readIDs == ["first"])
		store.shutdown()
	}

	@Test
	func observerRemovalAndShutdownAreScopedAndRetiredCallbacksCannotPublish() async
	{
		let service = RuntimeService()
		let otherService = RuntimeService()
		let reducer = WorkspaceReducer(reduceEffects:
			{
				model, action in
				if case .connection(.connectRequested(let context)) = action
				{
					return [.subscribe(context)]
				}
				if case .connection(.disconnected(
					let workspace,
					let generation,
					let message
				)) =
					action,
					workspace == model.identity, generation == model.connection.generation
				{
					model.connection.statusMessage = message
				}
				return []
			})
		let store = makeStore(
			service: service,
			reducers: [reducer]
		)
		let other = makeStore(
			service: otherService,
			reducers: [reducer]
		)
		var firstUpdates = 0
		var secondUpdates = 0
		let firstObserver = store.observe
		{
			_ in firstUpdates += 1
		}
		store.observe
		{
			_ in secondUpdates += 1
		}
		store.dispatch(.connection(.connectRequested(store.operationContext())))
		other.dispatch(.connection(.connectRequested(other.operationContext())))
		#expect(store.runningOperationCount == 0)
		let retired = service.onDisconnect
		store.removeObserver(firstObserver)
		service.onDisconnect?("offline")
		#expect(firstUpdates == 2)
		#expect(secondUpdates == 3)
		store.shutdown()
		retired?("late callback")
		#expect(store.model.connection.statusMessage == "offline")
		#expect(service.onDisconnect == nil)
		#expect(otherService.onDisconnect != nil)
		otherService.onDisconnect?("other offline")
		#expect(other.model.connection.statusMessage == "other offline")
		other.shutdown()
	}

	@Test
	func submissionHandleWaitsForPreparedReductionAndSuspendedTurnStart() async
	{
		let service = RuntimeService()
		let reducer = WorkspaceReducer(reduceEffects:
			{
				model, action in
				switch action
				{
				case .execution(.submissionRequested(let submission)):
					model.execution.owner = ExecutionOwner(submission: submission.context)
					return [.prepareSubmission(submission)]
				case .execution(.submissionPrepared(
					_,
					.succeeded(let prepared)
				)):
					model.conversations.selectedConversation = .thread(prepared.thread.summary.id)
					return [.startSubmission(prepared)]
				case .execution(.submissionAcknowledged(
					_,
					let acknowledgement
				)):
					model.execution.owner = ExecutionOwner(submission: OperationContext(
						workspace: model.identity,
						generation: model.connection.generation,
						requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
						threadID: acknowledgement.thread.id,
						turnID: acknowledgement.turn.id
					))
				default: break
				}
				return []
			})
		let store = makeStore(
			service: service,
			path: "/tmp",
			reducers: [reducer]
		)
		let context = store.operationContext()
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "hello"),
			inputs: [.text("hello")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		store.dispatch(.execution(.submissionRequested(submission)))
		let handle = store.operation(for: context)!
		await service.turnStarted.wait()
		#expect(store.model.conversations.selectedConversation == .thread("created"))
		#expect(handle.completion == nil)
		#expect(store.runningOperationCount == 1)
		service.completeTurn()
		#expect(await handle.wait() == .finished)
		#expect(handle.completion == .finished)
		#expect(store.model.execution.owner?.submission.turnID == "turn")
		#expect(store.runningOperationCount == 0)
		store.shutdown()
	}

	@Test
	func completedRequestRetentionIsBoundedAndCallerHandlesRemainUsable() async
	{
		let reducer = WorkspaceReducer(reduceEffects:
			{
				_, action in
				if case .preferences(.accountRefreshRequested(let context)) = action
				{
					return [.readAccount(context)]
				}
				return []
			})
		let store = makeStore(
			completedRequestLimit: 2,
			reducers: [reducer]
		)
		var retainedByCaller: [WorkspaceOperationHandle] = []
		for _ in 0 ..< 6
		{
			let context = store.operationContext()
			store.dispatch(.preferences(.accountRefreshRequested(context)))
			let handle = store.operation(for: context)!
			retainedByCaller.append(handle)
			#expect(await handle.wait() == .finished)
		}
		#expect(store.retainedOperationCount == 2)
		#expect(store.operation(for: retainedByCaller[0].context) == nil)
		#expect(await retainedByCaller[0].wait() == .finished)
		store.shutdown()
	}

	@Test
	func acceptedSelectionBarrierIncludesReducedChildPersistence() async throws
	{
		let service = RuntimeService()
		let writeStarted = RuntimeSignal()
		let releaseWrite = RuntimeSignal()
		let barrierStarted = RuntimeSignal()
		var barrierFinished = false
		let persistence = WorkspacePersistenceScheduler
		{
			_ in
			writeStarted.signal()
			await releaseWrite.wait()
		}
		// The runtime barrier must include a full selection read and any reduced child writes.
		let reducer = WorkspaceReducer(reduceEffects:
			{
				model, action in
				switch action
				{
				case .conversations(.selectionRequested(let context)):
					return [.readConversationHistory(ConversationReadOperation(
						context: context,
						commandRevision: 0,
						purpose: .selection
					))]
				case .conversations(.historyReceived(
					let operation,
					.succeeded
				)):
					model.execution.owner = ExecutionOwner(submission: operation.context)
					return [.persistDraft(WorkspaceDraftWrite(
						context: operation.context,
						conversation: .thread("selected"),
						draft: ComposerDraft(text: "discovered state")
					))]
				default: return []
				}
			})
		let store = makeStore(
			service: service,
			path: "/tmp",
			persistence: persistence,
			reducers: [reducer]
		)
		let context = store.operationContext(threadID: "selected")
		store.dispatch(.conversations(.selectionRequested(context)))
		await service.readStarted("selected")
		#expect(store.lifecycleObservation.pendingLocalWrites)
		let barrier = Task
		{
			barrierStarted.signal()
			try await store.awaitAcceptedPersistence()
			barrierFinished = true
		}
		await barrierStarted.wait()
		service.completeRead("selected")
		await writeStarted.wait()
		#expect(!barrierFinished)
		#expect(store.model.execution.owner?.submission == context)
		#expect(store.operation(for: context)?.completion == nil)
		releaseWrite.signal()
		try await barrier.value
		#expect(barrierFinished)
		#expect(store.operation(for: context)?.completion == .finished)
		store.shutdown()
	}

	@Test
	func sharedPersistenceOrdersSameKeyAtAcceptanceWithoutBlockingOtherKeys() async
	{
		let firstStarted = RuntimeSignal()
		let releaseFirst = RuntimeSignal()
		let otherWritten = RuntimeSignal()
		var writes: [String] = []
		let persistence = WorkspacePersistenceScheduler
		{
			write in
			if write.draft.text == "first"
			{
				firstStarted.signal()
				await releaseFirst.wait()
			}
			writes.append(write.draft.text)
			if write.draft.text == "other"
			{
				otherWritten.signal()
			}
		}
		let reducer = WorkspaceReducer(reduceEffects:
			{
				_, action in
				if case .composer(.draftRestored(
					let context,
					let conversation,
					let draft
				)) = action
				{
					return [.persistDraft(WorkspaceDraftWrite(
						context: context,
						conversation: conversation,
						draft: draft
					))]
				}
				return []
			})
		let first = makeStore(
			path: "/tmp",
			persistence: persistence,
			reducers: [reducer]
		)
		let second = makeStore(
			path: "/tmp",
			persistence: persistence,
			reducers: [reducer]
		)
		let firstContext = first.operationContext()
		let secondContext = second.operationContext()
		let otherContext = second.operationContext()
		first.dispatch(.composer(.draftRestored(
			firstContext,
			conversation: .newChat,
			draft: ComposerDraft(text: "first")
		)))
		second.dispatch(.composer(.draftRestored(
			secondContext,
			conversation: .newChat,
			draft: ComposerDraft(text: "second")
		)))
		second.dispatch(.composer(.draftRestored(
			otherContext,
			conversation: .thread("other"),
			draft: ComposerDraft(text: "other")
		)))
		await firstStarted.wait()
		await otherWritten.wait()
		#expect(writes == ["other"])
		releaseFirst.signal()
		#expect(await second.operation(for: secondContext)?.wait() == .finished)
		#expect(writes == ["other", "first", "second"])
		_ = await first.operation(for: firstContext)?.wait()
		_ = await second.operation(for: otherContext)?.wait()
		first.shutdown()
		second.shutdown()
	}

	private func makeStore(
		service: RuntimeService = RuntimeService(),
		path: String? = nil,
		persistence: WorkspacePersistenceScheduler? = nil,
		completedRequestLimit: Int = 128,
		reducers: [WorkspaceReducer]
	) -> WorkspaceStateStore
	{
		WorkspaceStateStore(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: path
			)),
			service: service,
			persistence: persistence ?? WorkspacePersistenceScheduler
			{
				_ in
			},
			reducers: reducers,
			completedRequestLimit: completedRequestLimit
		)
	}

	/// Deliberately a test reducer: Step 3 does not migrate production feature semantics.
	private func selectionReducer() -> WorkspaceReducer
	{
		WorkspaceReducer(reduceEffects:
			{
				model, action in
				switch action
				{
				case .conversations(.selectionRequested(let context)):
					guard context.belongsTo(
						workspace: model.identity,
						generation: model.connection.generation
					)
					else
					{
						return []
					}
					model.conversations.pendingSelection = context
					return [.readSelection(context), .readSelection(context)]
				case .conversations(.selectionReceived(
					let context,
					let result
				)):
					guard context.belongsTo(
						workspace: model.identity,
						generation: model.connection.generation
					),
						model.conversations.pendingSelection?.isSameRequest(as: context) == true
					else
					{
						return []
					}
					model.conversations.pendingSelection = nil
					switch result
					{
					case .succeeded(let detail): model.conversations.threads = [detail.summary]
					case .failed(let failure): model.conversations.error = failure.message
					}
				case .execution(.stopRequested(let context)): return [.cancel(context)]
				default: break
				}
				return []
			})
	}
}

@MainActor
private final class RuntimeSignal
{
	private var fired = false
	private var waiters: [CheckedContinuation<Void, Never>] = []
	func wait() async
	{
		guard !fired
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters.append($0)
		}
	}
	func signal()
	{
		fired = true
		let pending = waiters
		waiters.removeAll()
		for continuation in pending
		{
			continuation.resume()
		}
	}
}

@MainActor
private final class RuntimeService: CodexService
{
	var onEvent: ((AppServerEvent) -> Void)?
	var onDisconnect: ((String) -> Void)?
	var backendDiagnostics = BackendDiagnosticsSnapshot(
		cliVersion: nil,
		exitCode: nil,
		stderrTail: ""
	)
	var readIDs: [String] = []
	let turnStarted = RuntimeSignal()
	private var starts: [String: RuntimeSignal] = [:]
	private var returned: [String: RuntimeSignal] = [:]
	private var reads: [String: CheckedContinuation<ThreadDetail, Error>] = [:]
	private var turn: CheckedContinuation<CodexTurn, Error>?

	func readStarted(_ id: String) async
	{
		await signal(
			id,
			in: &starts
		).wait()
	}
	func readReturned(_ id: String) async
	{
		await signal(
			id,
			in: &returned
		).wait()
	}
	func completeRead(_ id: String)
	{
		reads.removeValue(forKey: id)?.resume(returning: detail(id))
	}
	func failRead(_ id: String)
	{
		reads.removeValue(forKey: id)?.resume(throwing: AppServerError.protocolError("read failed"))
	}
	func completeTurn()
	{
		turn?.resume(returning: CodexTurn(json: [
			"id": "turn",
			"status": "inProgress",
			"items": []
		])!)
		turn = nil
	}
	private func signal(
		_ id: String,
		in signals: inout [String: RuntimeSignal]
	) -> RuntimeSignal
	{
		if let existing = signals[id]
		{
			return existing
		}
		let created = RuntimeSignal()
		signals[id] = created
		return created
	}
	private func detail(_ id: String) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": id, "cwd": "/tmp"])!,
			turns: [],
			nextTurnsCursor: nil
		)
	}
	func executableVersion() async throws -> String
	{
		"fixture"
	}
	func connect() async throws
	{
	}
	func disconnect()
	{
	}
	func accountStatus() async throws -> AccountStatus
	{
		AccountStatus(
			type: "chatgpt",
			email: nil,
			requiresOpenAIAuth: true
		)
	}
	func startBrowserLogin() async throws -> URL
	{
		URL(string: "https://example.com")!
	}
	func models() async throws -> [ModelOption]
	{
		[]
	}
	func threads(for directory: URL) async throws -> [ThreadSummary]
	{
		[]
	}
	func startThread(
		in directory: URL,
		model: String?
	) async throws -> ThreadDetail
	{
		detail("created")
	}
	func resumeThread(id: String) async throws -> ThreadDetail
	{
		detail(id)
	}
	func readThread(id: String) async throws -> ThreadDetail
	{
		readIDs.append(id)
		defer
		{
			signal(
				id,
				in: &returned
			).signal()
		}
		return try await withCheckedThrowingContinuation
		{
			continuation in
			reads[id] = continuation
			signal(
				id,
				in: &starts
			).signal()
		}
	}
	func loadEarlierTurns(
		threadId: String,
		cursor: String
	) async throws
		-> (turns: [CodexTurn], nextCursor: String?)
	{
		([], nil)
	}
	func startTurn(
		threadId: String,
		text: String,
		model: String?,
		effort: String?
	) async throws -> CodexTurn
	{
		try await withCheckedThrowingContinuation
		{
			continuation in
			turn = continuation
			turnStarted.signal()
		}
	}
	func startTurn(
		threadId: String,
		inputs: [TurnInput],
		model: String?,
		effort: String?,
		skills: [SkillReference],
		cwd: URL?,
		preferences: RunPreferences
	) async throws -> CodexTurn
	{
		try await startTurn(
			threadId: threadId,
			text: "",
			model: model,
			effort: effort
		)
	}
	func steerTurn(
		threadId: String,
		expectedTurnId: String,
		text: String
	) async throws -> String
	{
		expectedTurnId
	}
	func interrupt(
		threadId: String,
		turnId: String
	) async throws
	{
	}
	func respond(
		to requestID: String,
		with response: InteractionResponse
	) throws
	{
	}
}
