import AppKit
import Foundation
import Testing

@testable import CodexGUI

// Each case owns a tiny checkout, context store, backends and defaults. Paired stores
// explicitly share that checkout; backend IDs never establish shared execution ownership.
@Suite("Captured workspace intents")
@MainActor
struct WorkspaceIntentRoutingTests
{
	@Test func newChatLifetimeRejectsRetainedComposerAndTaskDialogTargets() async throws
	{
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
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
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
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
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
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
		let aFixture = try await CapturedIntentStoreFixture.makeStore(threadID: "same-thread")
		defer
		{
			aFixture.cleanup()
		}
		let a = aFixture.store
		let serviceA = aFixture.service
		let bFixture = try await CapturedIntentStoreFixture.makeStore(
			threadID: "same-thread",
			sharing: aFixture
		)
		defer
		{
			bFixture.cleanup()
		}
		let b = bFixture.store
		let serviceB = bFixture.service
		await a.inputs.connect()
		await b.inputs.connect()
		for store in [a, b]
		{
			// Backend connection can finish before the independent project-context load.
			await waitForSubmissionReadiness(store)
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
		let storeFixture = try await CapturedIntentStoreFixture.makeStore(threadID: "reused-thread")
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
		await store.inputs.connect()
		// Backend connection can finish before the independent project-context load.
		await waitForSubmissionReadiness(store)
		store.inputs.updateDraft("First")
		let first = try #require(store.inputs.send())
		#expect(await first.wait() == .finished)
		let old = WorkspaceIntentTarget(
			store: store,
			snapshot: store.currentSnapshot
		)
		service.complete(status: "completed")
		await waitForSubmissionReadiness(store)
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

	@Test func approvalTargetKeepsImmutableSubmissionAffinityAcrossTurnAcknowledgement(
	) async throws
	{
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
		await store.inputs.connect()
		service.suspendTurnStart = true
		// Backend connection can finish before the independent project-context load.
		await waitForSubmissionReadiness(store)
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
		let storeFixture = try await CapturedIntentStoreFixture
			.makeStore(threadID: "recovered-thread")
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
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
		let storeFixture = try await CapturedIntentStoreFixture
			.makeStore(threadID: "reused-recovered-thread")
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
		service.savedTurns = [service.turn]
		await store.inputs.connect()
		if localSubmission
		{
			// Backend connection can finish before the independent project-context load.
			await waitForSubmissionReadiness(store)
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

	@Test func reconnectRetiresGenerationTargetsAndRenewsCardPresentationIdentity() async throws
	{
		let storeFixture = try await CapturedIntentStoreFixture.makeStore()
		defer
		{
			storeFixture.cleanup()
		}
		let store = storeFixture.store
		let service = storeFixture.service
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

	/// Context initialization and turn completion can outlast connection acknowledgement.
	/// Wait for the resulting published eligibility before creating the next submission.
	/// Yield counts measure scheduler activity, not acknowledgement of that read.
	private func waitForSubmissionReadiness(_ store: WorkspaceStateStore) async
	{
		await awaitWorkspaceSnapshot(
			store,
			matching:
			{
				$0.canSend
			}
		)
	}

}
