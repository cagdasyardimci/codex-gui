import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Captured workspace intents",
	.serialized
)
@MainActor
struct WorkspaceIntentRoutingTests
{
	@Test func newChatLifetimeRejectsRetainedComposerAndTaskDialogTargets() async throws
	{
		let (store, _) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(target.dispatch(.editDraft("Original")))
		store.inputs.newChat()
		#expect(store.currentSnapshot.draft == "Original")
		#expect(!target.dispatch(.editDraft("Late modal")))
		#expect(!target.accepts(.createTask("Late task")))
		#expect(!target.accepts(.renameProject(
			URL(fileURLWithPath: "/tmp"),
			"Late name"
		)))
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(current.dispatch(.editDraft("Current")))
		#expect(store.currentSnapshot.draft == "Current")
	}

	@Test func importedImagesRequireCapturedDraftAndReducerAcceptance() async throws
	{
		let (store, _) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let accepted = ComposerContextItem(
			kind: .image,
			title: "Accepted image",
			path: "/tmp/accepted-image.png"
		)
		#expect(target.attachImportedImage(accepted))
		#expect(store.model.composer.drafts[target.conversation]?.context
			.contains(accepted) == true)
		store.inputs.newChat()
		let rejected = ComposerContextItem(
			kind: .image,
			title: "Rejected image",
			path: "/tmp/rejected-image.png"
		)
		#expect(!target.attachImportedImage(rejected))
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(store.freezeInputsForQuit(WorkspaceQuitRequest(requestID: UUID())))
		#expect(!current.attachImportedImage(rejected))
		#expect(store.model.composer.drafts[current.conversation]?.context
			.contains(rejected) != true)
	}

	@Test func returningToTheSameStoreDoesNotReviveASelectedWindowCallback() async throws
	{
		let (store, _) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let coordinator = TaskWorkspaceCoordinator(sourceStore: store)
		defer
		{
			coordinator.shutdown()
		}
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: coordinator.currentSnapshot,
			coordinator: coordinator
		)
		coordinator.selectSourceCheckout()
		#expect(!target.dispatch(.editDraft("Obsolete selected window")))
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: coordinator.currentSnapshot,
			coordinator: coordinator
		)
		#expect(current.dispatch(.editDraft("New selection epoch")))
		#expect(store.currentSnapshot.draft == "New selection epoch")
	}

	@Test func approvalsAndStopKeepTheirExecutionOwnerWhileBrowsingAnotherConversation(
	) async throws
	{
		let (a, serviceA) = makeStore(threadID: "same-thread")
		let (b, serviceB) = makeStore(threadID: "same-thread")
		defer
		{
			a.shutdown()
			b.shutdown()
		}
		await a.inputs.connect()
		await b.inputs.connect()
		for store in [a, b]
		{
			store.inputs.updateDraft("Run")
			let submission = try #require(store.inputs.send())
			#expect(await submission.wait() == .finished)
		}
		try #require(a.model.execution.activeThreadID == serviceA.thread.id)
		try #require(a.model.execution.activeTurnID == serviceA.turn.id)
		let approval = serviceA.approval(id: "same-request")
		serviceA.emit(.interaction(approval))
		serviceB.emit(.interaction(serviceB.approval(id: "same-request")))
		let target = WorkspaceIntentTarget(
			store: a,
			snapshot: a.currentSnapshot
		)
		a.inputs.newChat()
		#expect(a.model.conversations.selectedConversation == .newChat)
		#expect(a.model.execution.activeTurnID == nil)
		try #require(a.model.execution(for: .thread(serviceA.thread.id)).activeTurnID
			== serviceA.turn.id)
		#expect(target.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let responseHandle = try #require(target.operation)
		#expect(await responseHandle.wait() == .finished)
		#expect(serviceA.respondedRequestIDs == ["same-request"])
		#expect(serviceB.respondedRequestIDs.isEmpty)
		#expect(b.model.execution.pendingInteractions.map(\.id) == ["same-request"])
		#expect(target.dispatch(.stop))
		let stopHandle = try #require(target.operation)
		#expect(await stopHandle.wait() == .finished)
		#expect(serviceA.interruptionRequests == [WorkspaceCodexService.TurnIdentity(
			threadID: "same-thread",
			turnID: serviceA.turn.id
		)])
		#expect(serviceB.interruptionRequests.isEmpty)
	}

	@Test func oldStopTicketCannotInterruptANewerSubmissionWithTheSameBackendIDs() async throws
	{
		let (store, service) = makeStore(threadID: "reused-thread")
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		store.inputs.updateDraft("First")
		let first = try #require(store.inputs.send())
		#expect(await first.wait() == .finished)
		let old = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		service.complete(status: "completed")
		for _ in 0 ..< 100
		{
			if store.currentSnapshot.canSend
			{
				break
			}
			await Task.yield()
		}
		store.inputs.updateDraft("Second")
		let second = try #require(store.inputs.send())
		#expect(await second.wait() == .finished)
		#expect(!old.dispatch(.stop))
		#expect(service.interruptionRequests.isEmpty)
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(current.dispatch(.stop))
		let handle = try #require(current.operation)
		#expect(await handle.wait() == .finished)
		#expect(service.interruptionRequests.count == 1)
	}

	@Test func retainedApprovalTargetCannotRespondToANewerSubmissionReusingItsTicketIDs(
	) async throws
	{
		let (store, service) = makeStore(threadID: "reused-thread")
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		store.inputs.updateDraft("First")
		let first = try #require(store.inputs.send())
		#expect(await first.wait() == .finished)
		let approval = service.approval(id: "reused-request")
		service.emit(.interaction(approval))
		let old = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(old.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let firstReply = try #require(old.operation)
		#expect(await firstReply.wait() == .finished)
		let firstOwnerID = try #require(store.model.execution.owner?.submission.requestID)
		service.complete(status: "completed")
		for _ in 0 ..< 100
		{
			if store.currentSnapshot.canSend
			{
				break
			}
			await Task.yield()
		}
		store.inputs.updateDraft("Second")
		let second = try #require(store.inputs.send())
		#expect(await second.wait() == .finished)
		#expect(store.model.execution.owner?.submission.requestID != firstOwnerID)
		service.emit(.interaction(service.approval(id: "reused-request")))
		#expect(!old.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		#expect(service.respondedRequestIDs == ["reused-request"])
		store.dispatch(.execution(.interactionResponseFinished(
			firstReply.context,
			.succeeded(())
		)))
		#expect(store.model.execution.pendingInteractions.map(\.id) == ["reused-request"])
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		store.inputs.newChat()
		#expect(current.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let secondReply = try #require(current.operation)
		#expect(await secondReply.wait() == .finished)
		#expect(service.respondedRequestIDs == ["reused-request", "reused-request"])
		#expect(store.model.execution.pendingInteractions.isEmpty)
	}

	@Test func approvalTargetKeepsImmutableSubmissionAffinityAcrossTurnAcknowledgement(
	) async throws
	{
		let (store, service) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		service.suspendTurnStart = true
		store.inputs.updateDraft("Run")
		let submission = try #require(store.inputs.send())
		await service.waitForCheckpoint("turnStart:1")
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let requestID = try #require(store.model.execution.owner?.submission.requestID)
		try #require(store.model.execution.submissionRequest != nil)
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.turn
		))
		service.savedTurns = [service.turn]
		let refresh = try #require(store.inputs.selectThread(service.thread.id))
		#expect(await refresh.wait() == .finished)
		#expect(store.model.execution.owner?.submission.requestID == requestID)
		let early = service.approval(id: "before-ack")
		service.emit(.interaction(early))
		#expect(target.dispatch(.respond(
			early,
			.approval(.accept)
		)))
		let earlyHandle = try #require(target.operation)
		#expect(await earlyHandle.wait() == .finished)
		service.pendingTurnStart?.resume(returning: service.turn)
		service.pendingTurnStart = nil
		#expect(await submission.wait() == .finished)
		#expect(store.model.execution.submissionRequest == nil)
		#expect(store.model.execution.owner?.submission.requestID == requestID)
		let acknowledged = service.approval(id: "after-ack")
		service.emit(.interaction(acknowledged))
		store.inputs.newChat()
		#expect(target.dispatch(.respond(
			acknowledged,
			.approval(.accept)
		)))
		let acknowledgedHandle = try #require(target.operation)
		#expect(await acknowledgedHandle.wait() == .finished)
		#expect(service.respondedRequestIDs == ["before-ack", "after-ack"])
	}

	@Test func freshlyRenderedRecoveredTurnApprovalHasAnImmutableOwner() async throws
	{
		let (store, service) = makeStore(threadID: "recovered-thread")
		defer
		{
			store.shutdown()
		}
		service.savedTurns = [service.turn]
		await store.inputs.connect()
		let history = try #require(store.inputs.selectThread(service.thread.id))
		#expect(await history.wait() == .finished)
		#expect(store.model.execution.activeThreadID == service.thread.id)
		#expect(store.model.execution.activeTurnID == service.turn.id)
		let ownerID = try #require(store.model.execution.owner?.submission.requestID)
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let refresh = try #require(store.inputs.selectThread(service.thread.id))
		#expect(await refresh.wait() == .finished)
		#expect(store.model.execution.owner?.submission.requestID == ownerID)
		let approval = service.approval(id: "recovered-approval")
		service.emit(.interaction(approval))
		try #require(store.model.execution.pendingInteractions.map(\.id) == [approval.id])
		store.inputs.newChat()
		#expect(target.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let reply = try #require(target.operation)
		#expect(await reply.wait() == .finished)
		#expect(service.respondedRequestIDs == [approval.id])
	}

	@Test(
		arguments: [false, true],
		[false, true]
	)
	func terminalOwnerCannotApproveNewHistoryWithReusedBackendIDs(
		localSubmission: Bool,
		eventBeforeRead: Bool
	) async throws
	{
		let (store, service) = makeStore(threadID: "reused-recovered-thread")
		defer
		{
			store.shutdown()
		}
		service.savedTurns = [service.turn]
		await store.inputs.connect()
		if localSubmission
		{
			store.inputs.updateDraft("First local turn")
			let submission = try #require(store.inputs.send())
			#expect(await submission.wait() == .finished)
		}
		else
		{
			let firstRead = try #require(store.inputs.selectThread(service.thread.id))
			#expect(await firstRead.wait() == .finished)
		}
		let old = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let oldOwnerID = try #require(store.model.execution.owner?.submission.requestID)
		let approval = service.approval(id: "reused-recovered-approval")
		service.emit(.interaction(approval))
		#expect(old.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let oldReply = try #require(old.operation)
		#expect(await oldReply.wait() == .finished)
		service.complete(status: "completed")
		let completionRead = try #require(store.model.conversations.pendingReads.values.first
		{
			$0.purpose == .completion
		})
		let completionHandle = try #require(store.operation(for: completionRead.context))
		#expect(await completionHandle.wait() == .finished)
		let terminalRead = try #require(store.inputs.selectThread(service.thread.id))
		#expect(await terminalRead.wait() == .finished)
		try #require(store.model.execution.activeTurnID == nil)
		service.savedTurns = [service.turn]
		if eventBeforeRead
		{
			service.emit(.turnStarted(
				threadId: service.thread.id,
				turn: service.turn
			))
		}
		#expect(!old.dispatch(.stop))
		let retiredOutcome = try #require(store.model.execution.agentOutcome)
		var stopContext = store.operationContext(threadID: service.thread.id)
		stopContext.turnID = service.turn.id
		store.dispatch(.execution(.stopRequested(stopContext)))
		#expect(!store.model.execution.stopRequested)
		#expect(service.interruptionRequests.isEmpty)
		store.dispatch(.execution(.historyObserved(
			ReconciliationOperation(
				context: store.operationContext(threadID: service.thread.id),
				commandRevision: store.model.execution.commandEventRevisions[service.thread.id,
																				default: 0],
				contentOnly: true
			),
			service.detail()
		)))
		#expect(store.model.execution.owner?.submission.requestID == oldOwnerID)
		#expect(store.model.execution.agentOutcome == retiredOutcome)
		let readContext = store.operationContext(threadID: service.thread.id)
		store.dispatch(.conversations(.historyRequested(ConversationReadOperation(
			context: readContext,
			commandRevision: store.model.execution.commandEventRevisions[service.thread.id,
																			default: 0],
			purpose: .selection
		))))
		let nextRead = try #require(store.operation(for: readContext))
		#expect(await nextRead.wait() == .finished)
		#expect(store.model.execution.owner?.submission.requestID != oldOwnerID)
		#expect(store.model.execution.activeTurnID == service.turn.id)
		service.emit(.interaction(approval))
		try #require(store.model.execution.pendingInteractions.map(\.id) == [approval.id])
		#expect(!old.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		store.dispatch(.execution(.interactionResponseFinished(
			oldReply.context,
			.succeeded(())
		)))
		#expect(store.model.execution.pendingInteractions.map(\.id) == [approval.id])
		#expect(service.respondedRequestIDs == [approval.id])
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(current.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let currentReply = try #require(current.operation)
		#expect(await currentReply.wait() == .finished)
		#expect(service.respondedRequestIDs == [approval.id, approval.id])
	}

	@Test func suspendedResponseCannotSettleAReplacementAfterTerminalRetirement() async throws
	{
		let (seed, service) = makeStore()
		defer
		{
			seed.shutdown()
		}
		await seed.inputs.connect()
		seed.inputs.updateDraft("First")
		let first = try #require(seed.inputs.send())
		#expect(await first.wait() == .finished)
		var responses: [WorkspaceEffect] = []
		var model = seed.model
		model.conversations.selectedConversation = .thread(service.thread.id)
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			persistence: seed.factoryDependencies.storage.workspacePersistenceScheduler,
			reducers: [WorkspaceReducer
			{
				model, action in
				var reduction = ExecutionReducer.reduce(
					&model,
					action
				)
				reduction.effects.removeAll
				{
					effect in
					if case .respond = effect
					{
						responses.append(effect)
						return true
					}
					return false
				}
				return reduction
			}]
		)
		var deliveries: [(WorkspaceAction, () -> Void)] = []
		let deliverySignals = AsyncStream<Void>.makeStream()
		var deliveryIterator = deliverySignals.stream.makeAsyncIterator()
		let runner = WorkspaceEffectRunner(
			service: service,
			persistence: seed.factoryDependencies.storage.workspacePersistenceScheduler,
			mapEvent:
			{
				_, _ in []
			},
			deliver:
			{
				action, complete in
				deliveries.append((action, complete))
				deliverySignals.continuation.yield(())
			}
		)
		defer
		{
			deliverySignals.continuation.finish()
			runner.shutdown()
			store.shutdown()
		}
		func observe(_ event: AppServerEvent)
		{
			store.dispatch(.execution(.backendObserved(
				store.operationContext(),
				event
			)))
		}
		let approval = service.approval(id: "suspended-reused-ticket")
		observe(.interaction(approval))
		let old = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(old.dispatch(.respond(
			approval,
			.approval(.accept)
		)))
		let oldContext = try #require(store.model.execution.pendingResponses[approval.id]?.context)
		runner.accept(
			responses,
			workspace: store.model.identity
		)
		responses.removeAll()
		let oldReply = try #require(runner.operation(for: oldContext))
		try #require(await deliveryIterator.next() != nil)
		#expect(oldReply.completion == nil)
		try #require(deliveries.count == 1)
		service.complete(status: "completed")
		observe(.turnCompleted(
			threadId: service.thread.id,
			turn: service.savedTurns[0]
		))
		#expect(store.model.execution.pendingResponses.isEmpty)
		observe(.turnStarted(
			threadId: service.thread.id,
			turn: service.turn
		))
		observe(.interaction(approval))
		var retiredContext = store.operationContext(threadID: service.thread.id)
		retiredContext.turnID = service.turn.id
		store.dispatch(.execution(.interactionResponseRequested(InteractionResponseOperation(
			context: retiredContext,
			interactionID: approval.id,
			response: .approval(.accept)
		))))
		#expect(responses.isEmpty)
		#expect(store.model.execution.pendingResponses.isEmpty)
		let replacementTurn = try #require(CodexTurn(json: [
			"id": "turn-two",
			"status": "inProgress",
			"items": [],
		]))
		let replacementApproval = PendingInteraction(
			id: approval.id,
			threadId: approval.threadId,
			turnId: replacementTurn.id,
			itemId: approval.itemId,
			approvalId: approval.approvalId,
			kind: approval.kind,
			reason: approval.reason,
			command: approval.command,
			cwd: approval.cwd,
			grantRoot: approval.grantRoot,
			networkHost: approval.networkHost,
			networkProtocol: approval.networkProtocol,
			questions: approval.questions,
			requestedPermissions: approval.requestedPermissions,
			additionalPermissions: approval.additionalPermissions,
			availableDecisions: approval.availableDecisions
		)
		observe(.turnStarted(
			threadId: service.thread.id,
			turn: replacementTurn
		))
		observe(.interaction(replacementApproval))
		service.savedTurns = [replacementTurn]
		let commandRevision = store.model.execution
			.commandEventRevisions[service.thread.id, default: 0]
		store.dispatch(.execution(.historyObserved(
			ReconciliationOperation(
				context: store.operationContext(threadID: service.thread.id),
				commandRevision: commandRevision
			),
			service.detail()
		)))
		let current = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		#expect(current.dispatch(.respond(
			replacementApproval,
			.approval(.accept)
		)))
		let currentContext = try #require(store.model.execution.pendingResponses[approval.id]?
			.context)
		#expect(currentContext.turnID == replacementTurn.id)
		#expect(currentContext != oldContext)
		runner.accept(
			responses,
			workspace: store.model.identity
		)
		let currentReply = try #require(runner.operation(for: currentContext))
		try #require(await deliveryIterator.next() != nil)
		#expect(oldReply.completion == nil)
		#expect(currentReply.completion == nil)
		try #require(deliveries.count == 2)
		store.dispatch(deliveries[0].0)
		deliveries[0].1()
		#expect(await oldReply.wait() == .finished)
		#expect(store.model.execution.pendingInteractions.map(\.id) == [approval.id])
		#expect(store.model.execution.pendingResponses[approval.id]?.context == currentContext)
		#expect(currentReply.completion == nil)
		#expect(service.respondedRequestIDs == [approval.id, approval.id])
		store.dispatch(deliveries[1].0)
		deliveries[1].1()
		#expect(await currentReply.wait() == .finished)
		#expect(store.model.execution.pendingInteractions.isEmpty)
		#expect(store.model.execution.pendingResponses.isEmpty)
	}

	@Test func reconnectRetiresGenerationTargetsAndRenewsCardPresentationIdentity() async throws
	{
		let (store, service) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let target = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let before = ConversationPresentation(
			store.currentSnapshot,
			ownerIdentity: target.presentationIdentity
		)
		service.onDisconnect?("Synthetic reconnect")
		await store.inputs.connect()
		#expect(!target.dispatch(.editDraft("Retired generation")))
		let renewed = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		let after = ConversationPresentation(
			store.currentSnapshot,
			ownerIdentity: renewed.presentationIdentity
		)
		#expect(before.interactions != after.interactions)
		#expect(renewed.dispatch(.editDraft("Current generation")))
		#expect(store.currentSnapshot.draft == "Current generation")
	}

	@Test func closedWindowDetachesItsStorePublicationObserver() async throws
	{
		_ = NSApplication.shared
		let (store, _) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		let controller = MainWindowController(
			store: store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		controller.showMessageSearch()
		controller.messageSearch.onSearch?("needle")
		#expect(store.model.contextNavigation.messageSearchContext != nil)
		var drafts: [String] = []
		controller.onSnapshot =
		{
			drafts.append($0.draft)
		}
		store.inputs.updateDraft("Visible")
		#expect(drafts == ["Visible"])
		controller.window?.close()
		#expect(store.model.contextNavigation.messageSearch == nil)
		#expect(store.model.contextNavigation.messageSearchContext == nil)
		#expect(store.model.contextNavigation.pendingMessageSearch == nil)
		store.inputs.updateDraft("Closed")
		#expect(drafts == ["Visible"])
	}

	@Test func searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding(
	) async throws
	{
		_ = NSApplication.shared
		let (first, service) = makeStore(threadID: "first-thread")
		let (next, _) = makeStore(threadID: "next-thread")
		defer
		{
			first.shutdown()
			next.shutdown()
		}
		await first.inputs.connect()
		await next.inputs.connect()
		let controller = MainWindowController(
			store: first,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		controller.showMessageSearch()
		let sheet = try #require(window.attachedSheet)
		controller.messageSearch.onSearch?("first query")
		_ = await first.inputs.selectThread(service.thread.id)?.wait()
		#expect(window.attachedSheet === sheet)
		#expect(first.model.contextNavigation.messageSearch?.query == "first query")
		first.inputs.newChat()
		#expect(window.attachedSheet === sheet)
		#expect(first.model.contextNavigation.messageSearchContext != nil)
		next.inputs.searchMessages("next query")
		controller.configureMessageSearchActions(target: WorkspaceIntentTarget(
			store: next,
			snapshot: next.currentSnapshot
		))
		#expect(window.attachedSheet == nil)
		#expect(first.model.contextNavigation.messageSearch == nil)
		#expect(first.model.contextNavigation.messageSearchContext == nil)
		#expect(first.model.contextNavigation.pendingMessageSearch == nil)
		#expect(next.model.contextNavigation.messageSearch?.query == "next query")
		#expect(next.model.contextNavigation.messageSearchContext != nil)
	}

	@Test func responseAdmissionKeepsTheFirstTicketAndAllowsRetryOnlyAfterSettlement() async throws
	{
		let (store, service) = makeStore()
		defer
		{
			store.shutdown()
		}
		await store.inputs.connect()
		store.inputs.updateDraft("Run")
		let submission = try #require(store.inputs.send())
		#expect(await submission.wait() == .finished)
		let approval = service.approval(id: "one-ticket")
		service.emit(.interaction(approval))
		var model = store.model
		func proposal() -> InteractionResponseOperation
		{
			var context = store.operationContext(threadID: approval.threadId)
			context.turnID = approval.turnId
			return InteractionResponseOperation(
				context: context,
				interactionID: approval.id,
				response: .approval(.accept)
			)
		}
		let first = proposal()
		let accepted = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(first))
		)
		#expect(accepted.effects.count == 1)
		if case .respond(let effect) = accepted.effects.first
		{
			#expect(effect.context == first.context)
		}
		else
		{
			Issue.record("First response did not emit its captured effect")
		}
		let duplicate = proposal()
		#expect(duplicate.context.requestID != first.context.requestID)
		let rejected = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(duplicate))
		)
		#expect(rejected.effects.isEmpty)
		#expect(model.execution.pendingResponses[approval.id]?.context == first.context)
		#expect(model.execution.pendingInteractions.map(\.id) == [approval.id])

		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				first.context,
				.failed(OperationFailure(
					message: "Synthetic response failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.execution.pendingResponses[approval.id] == nil)
		#expect(model.execution.pendingInteractions.map(\.id) == [approval.id])
		let retry = proposal()
		let retried = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(retry))
		)
		#expect(retried.effects.count == 1)
		#expect(model.execution.pendingResponses[approval.id]?.context == retry.context)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				first.context,
				.succeeded(())
			))
		)
		#expect(model.execution.pendingResponses[approval.id]?.context == retry.context)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseFinished(
				retry.context,
				.succeeded(())
			))
		)
		#expect(model.execution.pendingInteractions.isEmpty)
		#expect(ExecutionReducer.reduce(
			&model,
			.execution(.interactionResponseRequested(proposal()))
		).effects.isEmpty)
	}

	private func makeStore(threadID: String = "thread")
		-> (WorkspaceStateStore, WorkspaceCodexService)
	{
		let path = FileManager.default.temporaryDirectory.standardizedFileURL.path
		let service = WorkspaceCodexService(
			directory: URL(fileURLWithPath: path),
			threadID: threadID
		)
		let session = UUID()
		let identity = WorkspaceIdentity(
			sessionID: session,
			canonicalCheckoutPath: path
		)
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: session),
			workspace: identity
		)
		let storage = LocalStorage(defaults: UserDefaults(suiteName: "WorkspaceIntent.\(UUID())")!)
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(reference: reference),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: storage
			)
		)
		return (store, service)
	}
}
