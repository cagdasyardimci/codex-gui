import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ComposerReducerTests
{
	@Test func repeatedNewChatPreservesCapturedSubmissionAndRejectsItsLateDraftClear()
	{
		var (model, original) = fixture()
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID()
		)
		let item = ComposerContextItem(
			kind: .textExcerpt,
			title: "Unsent excerpt",
			path: "file.swift",
			excerpt: "value"
		)
		let draft = ComposerDraft(
			text: "submitted",
			context: [item],
			revision: 1,
			lifetime: 2
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: draft,
			inputs: original.inputs,
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.executions = ExecutionRegistry()
		model.composer.drafts[.newChat] = draft
		model.conversations.selectedConversation = .newChat
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.activeThreadID = "previous-owner"
		model.composer.pendingSubmissions = [context.requestID: submission]
		model.composer.submissionConversations = [context.requestID: .newChat]
		model.composer.drafts[.newChat] = draft
		model.conversations.selectedConversation = .newChat
		for _ in 0 ..< 2
		{
			let action = WorkspaceAction.conversations(.newChatOpened(OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID()
			)))
			_ = ComposerReducer.reduce(
				&model,
				action
			)
			_ = ConversationReducer.reduce(
				&model,
				action
			)
		}
		let independent = model.composer.drafts[.newChat]
		#expect(independent?.lifetime == 4)
		#expect(independent?.revision == 3)
		#expect(independent?.text == draft.text)
		#expect(independent?.context == draft.context)
		#expect(model.composer.pendingSubmissions[context.requestID]?.draft == draft)
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: acknowledgement().thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				context,
				.succeeded(prepared)
			))
		)
		let preparation = ComposerReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				context,
				.succeeded(prepared)
			))
		)
		let transfer = preparation.effects.compactMap
		{
			effect -> PreparedConversationWrite? in
			if case .persistPreparedConversation(let write) = effect
			{
				return write
			}
			return nil
		}.first
		#expect(transfer?.clearSource == false)
		#expect(transfer?.selectThread == false)
		_ = ComposerReducer.reduce(
			&model,
			.execution(.submissionAcknowledged(
				context,
				acknowledgement()
			))
		)
		#expect(model.composer.drafts[.newChat] == independent)
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.composer.pendingSubmissions[context.requestID]?.draft == draft)
	}

	@Test func newChatBeforeHydrationPreservesStoredContentAndRejectsObsoleteScope()
	{
		var (model, submission) = fixture()
		model.execution.state = .ready
		model.composer.drafts.removeValue(forKey: .newChat)
		let action = WorkspaceAction.conversations(.newChatOpened(submission.context))
		for _ in 0 ..< 2
		{
			_ = ComposerReducer.reduce(
				&model,
				action
			)
		}
		#expect(model.composer.drafts[.newChat] == nil)
		#expect(model.composer.pendingNewChatLifetime == 2)
		var stored = submission.draft
		stored.lifetime = 0
		_ = ComposerReducer.reduce(
			&model,
			.composer(.conversationRestored(
				submission.context,
				conversation: .newChat,
				draft: stored,
				references: []
			))
		)
		#expect(model.composer.drafts[.newChat]?.text == submission.draft.text)
		#expect(model.composer.drafts[.newChat]?.context == submission.draft.context)
		#expect(model.composer.drafts[.newChat]?.lifetime == 2)
		#expect(model.composer.pendingNewChatLifetime == nil)
		model.connection.generation += 1
		_ = ComposerReducer.reduce(
			&model,
			action
		)
		#expect(model.composer.drafts[.newChat]?.lifetime == 2)
	}

	@Test func storeNewChatRenewsModalLifetimeAndExactQuitLeaseRejectsRenewal() async throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("ComposerInteraction-\(UUID())")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let suite = "ComposerInteraction.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(defaults: defaults)
		let item = ComposerContextItem(
			kind: .textExcerpt,
			title: "Unsent excerpt",
			path: "file.swift",
			excerpt: "value"
		)
		storage.saveDraft(
			"Unsent text",
			for: directory,
			threadID: nil
		)
		storage.saveDraftContext(
			[item],
			for: directory,
			threadID: nil
		)
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: directory.resolvingSymlinksInPath().path
		)
		let service = WorkspaceCodexService(
			directory: directory,
			threadID: "thread"
		)
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(
				reference: WorkspaceLifecycleOwnerReference(
					owner: .source(sessionID: identity.sessionID),
					workspace: identity
				)
			),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: storage
			)
		)
		defer
		{
			store.shutdown()
		}
		let captured = store.currentSnapshot.composerDraftLifetime
		store.inputs.newChat()
		let first = store.currentSnapshot.composerDraftLifetime
		store.inputs.newChat()
		#expect(first > captured)
		#expect(store.currentSnapshot.composerDraftLifetime > first)
		#expect(store.currentSnapshot.draft == "Unsent text")
		#expect(store.currentSnapshot.draftContext == [item])
		try await store.awaitAcceptedPersistence()
		#expect(storage.draft(
			for: directory,
			threadID: nil
		) == "Unsent text")
		#expect(storage.draftContext(
			for: directory,
			threadID: nil
		) == [item])
		let request = WorkspaceQuitRequest(requestID: UUID())
		#expect(store.freezeInputsForQuit(request))
		let frozen = store.model.composer.drafts[.newChat]
		store.inputs.newChat()
		#expect(store.model.composer.drafts[.newChat] == frozen)
		store.thawInputsAfterQuit(request)
		#expect(service.turnRequests.isEmpty)
	}

	private func fixture() -> (WorkspaceModel, ComposerSubmission)
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/composer"
		)
		var model = WorkspaceModel(identity: identity)
		model.connection.generation = 1
		let context = OperationContext(
			workspace: identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		let draft = ComposerDraft(
			text: "submitted",
			revision: 1,
			lifetime: 2
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread("thread"),
			draft: draft,
			inputs: [.text("submitted")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.conversations.selectedConversation = .thread("thread")
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.state = .running
		model.execution.submissionRequest = context
		model.composer.drafts[.thread("thread")] = draft
		_ = ComposerReducer.reduce(
			&model,
			.execution(.submissionRequested(submission))
		)
		return (model, submission)
	}

	private func acknowledgement() -> SubmissionAcknowledgement
	{
		SubmissionAcknowledgement(
			thread: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/composer"])!,
			turn: CodexTurn(
				id: "turn",
				status: "inProgress",
				items: [],
				error: nil
			)
		)
	}

	@Test func replayingDurablyAcknowledgedSubmissionCannotRestartOrCaptureGhostRequest()
	{
		var (model, submission) = fixture()
		model.connection.isConnected = true
		model.execution.activeThreadID = "thread"
		let acknowledged = WorkspaceAction.execution(.submissionAcknowledged(
			submission.context,
			acknowledgement()
		))
		_ = ExecutionReducer.reduce(
			&model,
			acknowledged
		)
		_ = ComposerReducer.reduce(
			&model,
			acknowledged
		)
		let persisted = WorkspaceAction.execution(.draftAcknowledgementFinished(
			submission.context,
			.succeeded(SubmissionDraftAcknowledgement(
				submission: submission,
				threadID: "thread",
				cleared: true
			))
		))
		_ = ExecutionReducer.reduce(
			&model,
			persisted
		)
		_ = ComposerReducer.reduce(
			&model,
			persisted
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.submissionReleaseFinished(
				WorkspaceSubmissionReleaseOperation(
					context: submission.context,
					submission: submission
				),
				.succeeded(SubmissionReservationRelease(
					submission: submission,
					threadID: "thread",
					references: [],
					released: true
				))
			))
		)
		let completed = WorkspaceAction.execution(.backendObserved(
			submission.context,
			.turnCompleted(
				threadId: "thread",
				turn: CodexTurn(
					id: "turn",
					status: "completed",
					items: [],
					error: nil
				)
			)
		))
		_ = ExecutionReducer.reduce(
			&model,
			completed
		)
		_ = ComposerReducer.reduce(
			&model,
			completed
		)
		#expect(model.execution.state == .completed)
		#expect(model.composer.pendingSubmissions.isEmpty)
		let replay = WorkspaceAction.execution(.submissionRequested(submission))
		let execution = ExecutionReducer.reduce(
			&model,
			replay
		)
		let composer = ComposerReducer.reduce(
			&model,
			replay
		)
		#expect(execution.effects.isEmpty)
		#expect(composer.effects.isEmpty)
		#expect(model.execution.state == .completed)
		#expect(model.composer.pendingSubmissions.isEmpty)
	}

	@Test func rejectedSameOwnerSubmissionCannotCreateGhostCapturedRequest()
	{
		var (model, submission) = fixture()
		model.composer.pendingSubmissions.removeAll()
		model.composer.submissionConversations.removeAll()
		model.execution.submissionRequest = nil
		let reduction = ComposerReducer.reduce(
			&model,
			.execution(.submissionRequested(submission))
		)
		#expect(reduction.effects.isEmpty)
		#expect(model.composer.pendingSubmissions.isEmpty)
		#expect(model.composer.submissionConversations.isEmpty)
	}

	@Test func editAwayAndBackProducesAcknowledgementWithoutDraftClear()
	{
		var (model, submission) = fixture()
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				submission.context,
				conversation: .thread("thread"),
				text: "edited",
				revision: 2
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				submission.context,
				conversation: .thread("thread"),
				text: "submitted",
				revision: 3
			))
		)
		let reduction = ComposerReducer.reduce(
			&model,
			.execution(.submissionAcknowledged(
				submission.context,
				acknowledgement()
			))
		)
		#expect(model.composer.drafts[.thread("thread")]?.revision == 3)
		#expect(model.composer.drafts[.thread("thread")]?.text == "submitted")
		let write = reduction.effects.compactMap
		{
			effect -> SubmissionAcknowledgementWrite? in
			if case .acknowledgeSubmission(let write) = effect
			{
				return write
			}
			return nil
		}.first
		#expect(write != nil)
		#expect(write?.draft == nil)
	}

	@Test func anotherDraftLifetimeWithIdenticalTextSurvivesAcknowledgement()
	{
		var (model, submission) = fixture()
		model.composer.drafts[.thread("thread")] = ComposerDraft(
			text: submission.draft.text,
			revision: submission.draft.revision,
			lifetime: submission.draft.lifetime + 1
		)
		_ = ComposerReducer.reduce(
			&model,
			.execution(.submissionAcknowledged(
				submission.context,
				acknowledgement()
			))
		)
		#expect(model.composer.drafts[.thread("thread")]?.text == "submitted")
		#expect(model.composer.drafts[.thread("thread")]?.lifetime == 3)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
	}

	@Test func preparedNewChatDoesNotAdoptOrClearAnIndependentDraftLifetime()
	{
		var (model, existing) = fixture()
		var context = existing.context
		context.threadID = nil
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: existing.draft,
			inputs: existing.inputs,
			skills: existing.skills,
			modelID: existing.modelID,
			effort: existing.effort,
			preferences: existing.preferences,
			retainedContextRequestID: existing.retainedContextRequestID
		)
		var execution = ExecutionModel()
		execution.owner = ExecutionOwner(submission: context)
		execution.submissionRequest = context
		execution.state = .running
		model.executions = ExecutionRegistry()
		model.executions.entries[.newChat(lifetime: submission.draft.lifetime)] = execution
		model.composer.pendingSubmissions[context.requestID] = submission
		model.composer.submissionConversations[context.requestID] = .newChat
		model.conversations.selectedConversation = .newChat
		let independent = ComposerDraft(
			text: submission.draft.text,
			revision: submission.draft.revision,
			lifetime: submission.draft.lifetime + 1
		)
		model.composer.drafts[.newChat] = independent
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: acknowledgement().thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared)
			))
		)
		let reduction = ComposerReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submission.context,
				.succeeded(prepared)
			))
		)
		let write = reduction.effects.compactMap
		{
			effect -> PreparedConversationWrite? in
			if case .persistPreparedConversation(let write) = effect
			{
				return write
			}
			return nil
		}.first
		#expect(write != nil)
		#expect(write?.clearSource == false)
		#expect(write?.selectThread == false)
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.composer.drafts[.newChat] == independent)
		#expect(model.composer.drafts[.thread("thread")] == submission.draft)
		#expect(model.execution(for: .thread("thread")).activeThreadID == "thread")
		#expect(model.execution(for: .thread("thread")).owner?.submission.requestID
			== context.requestID)
		#expect(model.execution.owner == nil)
	}

	@Test func obsoleteAcknowledgementsAndOlderDraftRestorationCannotClearCurrentEdit()
	{
		var (model, submission) = fixture()
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				submission.context,
				conversation: .thread("thread"),
				text: "current edit",
				revision: 2
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftRestored(
				submission.context,
				conversation: .thread("thread"),
				draft: submission.draft
			))
		)
		let olderGeneration = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: submission.context.requestID,
			threadID: "thread"
		)
		let anotherRequest = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		for context in [olderGeneration, anotherRequest]
		{
			let reduction = ComposerReducer.reduce(
				&model,
				.execution(.submissionAcknowledged(
					context,
					acknowledgement()
				))
			)
			#expect(reduction.effects.isEmpty)
		}
		#expect(model.composer.drafts[.thread("thread")]?.text == "current edit")
		#expect(model.composer.drafts[.thread("thread")]?.revision == 2)
	}

	@Test func obsoleteDisconnectCannotMarkCurrentSubmissionUncertain()
	{
		var (model, submission) = fixture()
		model.connection.generation = 3
		model.connection.isConnected = false
		let reduction = ComposerReducer.reduce(
			&model,
			.connection(.disconnected(
				workspace: model.identity,
				generation: 0,
				message: "obsolete"
			))
		)
		#expect(reduction.effects.isEmpty)
		#expect(model.composer.uncertainSubmissions.isEmpty)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
	}

	@Test func openingSameProjectWhileBusyPreservesComposerOwnership()
	{
		var (model, submission) = fixture()
		_ = ComposerReducer.reduce(
			&model,
			.connection(.projectOpened(
				model.identity,
				selectedThreadID: "other"
			))
		)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
		#expect(model.composer.drafts[.thread("thread")] == submission.draft)
	}

	@Test func staleDraftWriteFailureCannotReplaceNewerWriteStatus()
	{
		var (model, submission) = fixture()
		let newer = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				submission.context,
				conversation: .thread("thread"),
				text: "first edit",
				revision: 2
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				newer,
				conversation: .thread("thread"),
				text: "newer edit",
				revision: 3
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftPersistenceFinished(
				submission.context,
				.failed(OperationFailure(
					message: "obsolete failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.composer.persistenceError == nil)
		#expect(model.composer.pendingDraftWrites[.thread("thread")] == newer.requestID)
		#expect(model.composer.drafts[.thread("thread")]?.text == "newer edit")
	}

	@Test func replayedRecoveryTokenCannotReleaseOwnershipAfterNewerCommandEvidence()
	{
		var (model, submission) = fixture()
		model.conversations.selectedConversation = .thread("thread")
		model.execution.needsReconciliation = true
		model.composer.uncertainSubmissions.insert(submission.context.requestID)
		let detail = ThreadDetail(
			summary: acknowledgement().thread,
			turns: [],
			nextTurnsCursor: nil
		)
		let operation = ReconciliationOperation(
			context: submission.context,
			commandRevision: 0
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				operation,
				detail
			))
		)
		#expect(model.execution.lastReconciledRequestID == submission.context.requestID)
		let command = CodexItem(json: ["id": "command",
										"type": "commandExecution",
										"status": "inProgress"])!
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				submission.context,
				.itemStarted(
					threadId: "thread",
					turnId: "turn",
					item: command
				)
			))
		)
		#expect(model.execution.commandEventRevisions["thread", default: 0] > 0)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.historyObserved(
				operation,
				detail
			))
		)
		let rejected = ComposerReducer.reduce(
			&model,
			.execution(.historyObserved(
				operation,
				detail
			))
		)
		#expect(model.execution.lastReconciledRequestID == nil)
		#expect(rejected.effects.isEmpty)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
		#expect(model.composer.uncertainSubmissions.contains(submission.context.requestID))
	}

	@Test func oldReleaseFailureCannotRetireOrOverwriteNewerRetry()
	{
		var (model, submission) = fixture()
		let retry = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		model.composer.resolvingSubmissions[submission.context.requestID] = retry
		model.composer.persistenceFailure = ComposerPersistenceFailure(
			context: retry,
			key: .submission(submission.context.requestID),
			message: "current failure"
		)
		let old = WorkspaceSubmissionReleaseOperation(
			context: submission.context,
			submission: submission
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.submissionReleaseFinished(
				old,
				.failed(OperationFailure(
					message: "obsolete failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.composer.resolvingSubmissions[submission.context.requestID] == retry)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
		#expect(model.composer.persistenceError == "current failure")
	}

	@Test func successfulDraftWriteClearsOnlyMatchingDraftPersistenceFailure()
	{
		var (model, submission) = fixture()
		let other = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "other"
		)
		model.composer.persistenceFailure = ComposerPersistenceFailure(
			context: submission.context,
			key: .draft(.thread("thread")),
			message: "draft failure"
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				other,
				conversation: .thread("other"),
				text: "other",
				revision: 1
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftPersistenceFinished(
				other,
				.succeeded(())
			))
		)
		#expect(model.composer.persistenceError == "draft failure")
		let matching = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				matching,
				conversation: .thread("thread"),
				text: "later",
				revision: 2
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftPersistenceFinished(
				matching,
				.succeeded(())
			))
		)
		#expect(model.composer.persistenceError == nil)
		model.composer.persistenceFailure = ComposerPersistenceFailure(
			context: submission.context,
			key: .submission(submission.context.requestID),
			message: "release failure"
		)
		let subsequent = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftEdited(
				subsequent,
				conversation: .thread("thread"),
				text: "newest",
				revision: 3
			))
		)
		_ = ComposerReducer.reduce(
			&model,
			.composer(.draftPersistenceFinished(
				subsequent,
				.succeeded(())
			))
		)
		#expect(model.composer.persistenceError == "release failure")
	}

	@Test func uncertainResultRetainsCapturedSubmissionUntilAcceptedReconciliation()
	{
		var (model, submission) = fixture()
		model.execution.needsReconciliation = true
		_ = ComposerReducer.reduce(
			&model,
			.execution(.submissionFailed(
				submission.context,
				OperationFailure(
					message: "uncertain",
					outcomeIsUncertain: true
				)
			))
		)
		#expect(model.composer.uncertainSubmissions.contains(submission.context.requestID))
		let detail = ThreadDetail(
			summary: acknowledgement().thread,
			turns: [],
			nextTurnsCursor: nil
		)
		let stillUnresolved = ComposerReducer.reduce(
			&model,
			.execution(.reconciliationFinished(
				submission.context,
				.succeeded(detail)
			))
		)
		#expect(stillUnresolved.effects.isEmpty)
		#expect(model.composer.pendingSubmissions[submission.context.requestID] != nil)
		model.execution.needsReconciliation = false
		model.execution.lastReconciledRequestID = submission.context.requestID
		let resolved = ComposerReducer.reduce(
			&model,
			.execution(.reconciliationFinished(
				submission.context,
				.succeeded(detail)
			))
		)
		#expect(!resolved.effects.isEmpty)
		#expect(model.composer.drafts[.thread("thread")]?.text == submission.draft.text)
		#expect(model.composer.drafts[.thread("thread")]?.context == submission.draft.context)
		#expect(model.composer.drafts[.thread("thread")]?.revision != submission.draft.revision)
	}

	@Test func validRevisionPrependsExactSourceToDraftWithoutSteering() throws
	{
		var model = reviewFixture()
		model.composer.drafts[.thread("thread")] = ComposerDraft(
			text: "Keep existing draft",
			revision: 4
		)
		let turn = try #require(ReviewReducer.selectedTurn(
			model,
			.thread("thread")
		))
		let file = try #require(turn.files.first)
		let hunk = try #require(file.hunks.first)
		let reference = ReviewReference(
			threadID: "thread",
			turnID: turn.turnID,
			file: file,
			hunk: hunk
		)
		let request = ChangeRequest(
			reference: reference,
			file: file,
			hunk: hunk,
			kind: .revision,
			sourceRevision: 1
		)
		let result = ComposerReducer.reduce(
			&model,
			.review(.changeRequestPrepared(
				reviewContext(model),
				request
			))
		)
		let draft = try #require(model.composer.drafts[.thread("thread")])
		#expect(draft.text == reference.prompt(
			for: .revision,
			file: file,
			hunk: hunk
		)
			+ "Keep existing draft")
		#expect(draft.revision == 5)
		#expect(result.effects.count == 1)
		guard case .persistDraft = result.effects[0]
		else
		{
			Issue.record("Revision preparation must only persist its composed draft.")
			return
		}
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let stale = ComposerReducer.reduce(
			&model,
			.review(.changeRequestPrepared(
				reviewContext(model),
				request
			))
		)
		#expect(stale.effects.isEmpty)
		#expect(model.composer.drafts[.thread("thread")]?.revision == 5)
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				reviewContext(model),
				conversation: .thread("thread"),
				turnID: "first"
			))
		)
		#expect(!ReviewReducer.accepts(
			reviewContext(model),
			request,
			model: model
		))
	}

	private func reviewTurn(
		_ id: String,
		addition: String = "new"
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": "change-\(id)",
				"type": "fileChange",
				"status": "completed",
				"changes": [["path": "Sources/A.swift",
								"kind": "update",
								"diff": "@@ -1 +1 @@\n-old\n+\(addition)\n"]]
			])!],
			error: nil
		)
	}

	private func reviewFixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/review"
		))
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [reviewTurn("first"), reviewTurn("latest")],
			reviewSourceRevision: 1
		)
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				reviewContext(model),
				conversation: .thread("thread"),
				turnID: "latest"
			))
		)
		return model
	}

	private func reviewContext(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
	}
}
