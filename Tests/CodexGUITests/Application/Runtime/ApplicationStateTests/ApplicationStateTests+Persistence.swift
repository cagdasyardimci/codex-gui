import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func completedTextWriteFailureRemainsVisibleToDrainUntilSameKeySucceeds() async throws
	{
		var shouldFail = true
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				_ in
				if shouldFail
				{
					throw AppServerError.protocolError("text write failed")
				}
			})
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/drain"
		)
		func write(_ threadID: String) -> WorkspaceDraftWrite
		{
			WorkspaceDraftWrite(
				context: OperationContext(
					workspace: identity,
					generation: 0,
					requestID: UUID()
				),
				conversation: .thread(threadID),
				draft: ComposerDraft(text: "text only")
			)
		}
		let failed = await scheduler.enqueue(write("original")).result
		if case .success = failed
		{
			Issue.record("Expected failed text persistence")
		}
		do
		{
			try await scheduler.drain()
			Issue.record("Drain forgot the completed text-only failure")
		}
		catch
		{
		}
		shouldFail = false
		try await scheduler.enqueue(write("unrelated")).value
		do
		{
			try await scheduler.drain()
			Issue.record("An unrelated key cleared the failed transaction")
		}
		catch
		{
		}
		try await scheduler.enqueue(write("original")).value
		try await scheduler.drain()
	}

	@Test func partialReplacementCannotClearCompletedMultiKeyTransferFailure() async throws
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/drain"
		)
		let context = OperationContext(
			workspace: identity,
			generation: 0,
			requestID: UUID()
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "transfer"),
			inputs: [.text("transfer")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: MockCodexService().thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		var failDestination = true
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				if failDestination, case .thread = write.conversation
				{
					throw AppServerError.protocolError("destination failed")
				}
			})
		let transfer = PreparedConversationWrite(
			prepared: prepared,
			draft: submission.draft,
			selectThread: false
		)
		let failed = await scheduler.enqueue(transfer).result
		if case .success = failed
		{
			Issue.record("Expected failed transfer")
		}
		failDestination = false
		try await scheduler.enqueue(WorkspaceDraftWrite(
			context: context,
			conversation: .newChat,
			draft: ComposerDraft(text: "source only")
		)).value
		do
		{
			try await scheduler.drain()
			Issue.record("Replacing only the source cleared a multi-key failure")
		}
		catch
		{
		}
		try await scheduler.enqueue(transfer).value
		try await scheduler.drain()
	}

	@Test func releaseRetryRejectsOldResultAndPreservesEditedDraft() async throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let image = directory.appendingPathComponent("leased.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let suite = "ComposerReleaseRetry.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: directory)
		)
		let project = URL(fileURLWithPath: "/tmp")
		let gate = PublicationGate()
		var referenceWrites = 0
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				write in
				guard case .thread(let threadID) = write.conversation
				else
				{
					return
				}
				storage.saveDraft(
					write.draft.text,
					for: project,
					threadID: threadID
				)
				storage.saveDraftContext(
					write.draft.context,
					for: project,
					threadID: threadID
				)
			},
			rememberReferences:
			{
				write in
				referenceWrites += 1
				if referenceWrites ==
					1
				{
					throw AppServerError.protocolError("reference write failed")
				}
				await gate.wait()
				storage.rememberSentReferences(
					write.items,
					for: project,
					threadID: write.threadID
				)
			}
		)
		let service = MockCodexService()
		service.startTurnError = AppServerError.requestTimedOut("turn/start")
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project
				.standardizedFileURL
				.resolvingSymlinksInPath().path
		))
		model.connection.isConnected = true
		model.execution.state = .ready
		model.conversations.selectedConversation = .thread(service.thread.id)
		let attachment = ComposerContextItem(
			kind: .image,
			title: "Lease",
			path: image.path
		)
		let draft = ComposerDraft(
			text: "submitted",
			context: [attachment],
			revision: 1
		)
		model.composer.drafts[.thread(service.thread.id)] = draft
		storage.saveDraftContext(
			[attachment],
			for: project,
			threadID: service.thread.id
		)
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			storage: storage,
			persistence: scheduler,
			reducers: [WorkspaceFeatureComposition.reducer],
			reduceDomainEvent: ConversationReviewComposition.reduceDomainEvent
		)
		defer
		{
			store.shutdown()
		}
		let original = store.operationContext(threadID: service.thread.id)
		let submission = ComposerSubmission(
			context: original,
			conversation: .thread(service.thread.id),
			draft: draft,
			inputs: try ComposerContextBuilder.inputs(
				text: draft.text,
				items: draft.context,
				project: project
			),
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		store.dispatch(.execution(.submissionRequested(submission)))
		_ = await store.operation(for: original)?.wait()
		try #require(store.model.execution.hasUncertainRequest)
		let edit = store.operationContext(threadID: service.thread.id)
		store.dispatch(.composer(.draftEdited(
			edit,
			conversation: .thread(service.thread.id),
			text: "edited draft",
			revision: 2
		)))
		_ = await store.operation(for: edit)?.wait()
		let remove = store.operationContext(threadID: service.thread.id)
		store.dispatch(.composer(.contextRemoved(
			remove,
			conversation: .thread(service.thread.id),
			itemID: attachment.id,
			revision: 3
		)))
		_ = await store.operation(for: remove)?.wait()
		#expect(FileManager.default.fileExists(atPath: image.path))
		let firstRecovery = store.operationContext(threadID: service.thread.id)
		store.dispatch(.conversations(.historyRequested(ConversationReadOperation(
			context: firstRecovery,
			commandRevision: 0,
			purpose: .recovery
		))))
		_ = await store.operation(for: firstRecovery)?.wait()
		#expect(referenceWrites == 1)
		#expect(store.model.composer.pendingSubmissions[original.requestID] != nil)
		let retry = store.operationContext(threadID: service.thread.id)
		#expect(!store.model.execution.needsReconciliation)
		#expect(!store.model.execution.hasUncertainRequest)
		store.dispatch(.conversations(.historyRequested(ConversationReadOperation(
			context: retry,
			commandRevision: 0,
			purpose: .search
		))))
		try #require(await waitUntil
		{
			gate.isWaiting
		})
		#expect(referenceWrites == 2)
		let obsolete = WorkspaceSubmissionReleaseOperation(
			context: firstRecovery,
			submission: submission
		)
		store.dispatch(.composer(.submissionReleaseFinished(
			obsolete,
			.succeeded(SubmissionReservationRelease(
				submission: submission,
				threadID: service.thread.id,
				references: [],
				released: true
			))
		)))
		#expect(store.model.composer.pendingSubmissions[original.requestID] != nil)
		#expect(store.model.composer.resolvingSubmissions[original.requestID] == retry)
		gate.release()
		#expect(await store.operation(for: retry)?.wait() == .finished)
		#expect(store.model.composer.pendingSubmissions[original.requestID] == nil)
		#expect(store.model.composer.resolvingSubmissions[original.requestID] == nil)
		#expect(store.model.composer.drafts[.thread(service.thread.id)]?.text == "edited draft")
		#expect(store.model.composer.drafts[.thread(service.thread.id)]?.context.isEmpty == true)
		#expect(storage.sentReferences(
			for: project,
			threadID: service.thread.id
		) == [attachment])
		#expect(FileManager.default.fileExists(atPath: image.path))
		try await scheduler.drain()
	}

	@Test func pendingAttachmentWriteRetainsImageWhileAnotherStoreRemovesItsLastSavedReference(
	) async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let directory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let image = directory.appendingPathComponent("pending-write.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let attachment = ComposerContextItem(
			kind: .image,
			title: "Pending",
			path: image.path
		)
		let suite = "ComposerPendingWrite.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: directory)
		)
		storage.saveDraftContext(
			[attachment],
			for: project,
			threadID: "B"
		)
		let gate = PublicationGate()
		let scheduler = WorkspacePersistenceScheduler(
			writeDraft:
			{
				write in
				guard case .thread(let threadID) = write.conversation
				else
				{
					return
				}
				if threadID == "A"
				{
					await gate.wait()
				}
				storage.saveDraftContext(
					write.draft.context,
					for: project,
					threadID: threadID
				)
			},
			rememberReferences:
			{
				_ in
			},
			reserveContext:
			{
				storage.retainContextForRequest($0)
			},
			releaseContext:
			{
				storage.releaseContextForRequest($0)
			}
		)
		func makeStore() -> WorkspaceStateStore
		{
			WorkspaceStateStore(
				model: WorkspaceModel(identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: project.path
				)),
				service: MockCodexService(),
				persistence: scheduler,
				reducers: [ComposerReducer.reducer]
			)
		}
		let first = makeStore()
		let second = makeStore()
		defer
		{
			first.shutdown()
			second.shutdown()
		}
		let firstContext = first.operationContext(threadID: "A")
		let secondContext = second.operationContext(threadID: "B")
		second.dispatch(.composer(.draftRestored(
			secondContext,
			conversation: .thread("B"),
			draft: ComposerDraft(
				context: [attachment],
				revision: 1
			)
		)))
		first.dispatch(.composer(.contextAttached(
			firstContext,
			conversation: .thread("A"),
			item: attachment,
			revision: 1
		)))
		try #require(await waitUntil
		{
			gate.isWaiting
		})
		second.dispatch(.composer(.contextRemoved(
			secondContext,
			conversation: .thread("B"),
			itemID: attachment.id,
			revision: 2
		)))
		#expect(await second.operation(for: secondContext)?.wait() == .finished)
		#expect(storage.draftContext(
			for: project,
			threadID: "B"
		).isEmpty)
		#expect(storage.draftContext(
			for: project,
			threadID: "A"
		).isEmpty)
		#expect(FileManager.default.fileExists(atPath: image.path))
		gate.release()
		#expect(await first.operation(for: firstContext)?.wait() == .finished)
		#expect(storage.draftContext(
			for: project,
			threadID: "A"
		) == [attachment])
		#expect(FileManager.default.fileExists(atPath: image.path))
	}

	@Test func sharedSchedulerOrdersSameDraftKeyAcrossActualWorkspaceStores() async throws
	{
		let gate = PublicationGate()
		var writes: [String] = []
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				if write.draft.text == "first"
				{
					await gate.wait()
				}
				writes.append(write.draft.text)
			})
		func makeStore() -> WorkspaceStateStore
		{
			WorkspaceStateStore(
				model: WorkspaceModel(identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: "/tmp/shared-composer"
				)),
				service: MockCodexService(),
				persistence: scheduler,
				reducers: [ComposerReducer.reducer]
			)
		}
		let first = makeStore()
		let second = makeStore()
		defer
		{
			first.shutdown()
			second.shutdown()
		}
		let firstContext = first.operationContext(threadID: "same-thread")
		let secondContext = second.operationContext(threadID: "same-thread")
		first.dispatch(.composer(.draftEdited(
			firstContext,
			conversation: .thread("same-thread"),
			text: "first",
			revision: 1
		)))
		try #require(await waitUntil
		{
			gate.isWaiting
		})
		second.dispatch(.composer(.draftEdited(
			secondContext,
			conversation: .thread("same-thread"),
			text: "second",
			revision: 1
		)))
		let secondHandle = try #require(second.operation(for: secondContext))
		#expect(second.model.composer.drafts[.thread("same-thread")]?.text == "second")
		#expect(secondHandle.completion == nil)
		#expect(writes.isEmpty)
		gate.release()
		#expect(await first.operation(for: firstContext)?.wait() == .finished)
		#expect(await secondHandle.wait() == .finished)
		#expect(writes == ["first", "second"])
	}

	@Test func preparedTransferWritesDestinationBeforeSourceClearAndLaterStoreEdit() async throws
	{
		let gate = PublicationGate()
		let submittedDraft = ComposerDraft(
			text: "submitted",
			revision: 1
		)
		var persisted: [ConversationKey: String] = [.newChat: "submitted"]
		var writes: [ConversationKey] = []
		let scheduler = WorkspacePersistenceScheduler(writeDraft:
			{
				write in
				if write.conversation == .thread("thread-1")
				{
					await gate.wait()
				}
				persisted[write.conversation] = write.draft.text
				writes.append(write.conversation)
			})
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/shared-composer"
		)
		let context = OperationContext(
			workspace: identity,
			generation: 0,
			requestID: UUID()
		)
		let service = MockCodexService()
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: submittedDraft,
			inputs: [.text("submitted")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		var model = WorkspaceModel(identity: identity)
		model.composer.drafts[.newChat] = submittedDraft
		model.composer.pendingSubmissions[context.requestID] = submission
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.submissionRequest = context
		let first = WorkspaceStateStore(
			model: model,
			service: service,
			persistence: scheduler,
			reducers: [ComposerReducer.reducer]
		)
		let second = WorkspaceStateStore(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/shared-composer"
			)),
			service: MockCodexService(),
			persistence: scheduler,
			reducers: [ComposerReducer.reducer]
		)
		defer
		{
			first.shutdown()
			second.shutdown()
		}
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: service.thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		first.dispatch(.execution(.submissionPrepared(
			context,
			.succeeded(prepared)
		)))
		try #require(await waitUntil
		{
			gate.isWaiting
		})
		#expect(persisted[.newChat] == "submitted")
		#expect(persisted[.thread(service.thread.id)] == nil)
		let secondContext = second.operationContext()
		second.dispatch(.composer(.draftEdited(
			secondContext,
			conversation: .newChat,
			text: "later independent draft",
			revision: 1
		)))
		let secondHandle = try #require(second.operation(for: secondContext))
		#expect(secondHandle.completion == nil)
		gate.release()
		#expect(await first.operation(for: context)?.wait() == .finished)
		#expect(await secondHandle.wait() == .finished)
		#expect(writes == [.thread(service.thread.id), .newChat, .newChat])
		#expect(persisted[.thread(service.thread.id)] == "submitted")
		#expect(persisted[.newChat] == "later independent draft")
	}

	@Test func renamingSelectedThreadCallsServiceAndReleasesManagementLock() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canManageThreads
		})

		state.inputs.renameSelectedThread("  Clear name  ")
		#expect(!state.currentSnapshot.canManageThreads)
		#expect(
			await waitUntil
			{
				service.renamedThreads.count == 1
					&& state.currentSnapshot.canManageThreads
			}
		)
		#expect(service.renamedThreads.first?.0 == service.thread.id)
		#expect(service.renamedThreads.first?.1 == "Clear name")
	}

	@Test func obsoletePageCannotClearOrOverwriteNewConnectionRequest() async throws
	{
		for obsoleteFirst in [false, true]
		{
			let project = try makeProject()
			defer
			{
				try? FileManager.default.removeItem(at: project)
			}
			let service = MockCodexService()
			service.readNextCursor = "older"
			service.savedTurns = [makeTurn(
				id: "latest",
				status: "completed"
			)]
			let state = WorkspaceTestFixture(
				server: service,
				storage: makeStorage()
			)
			await state.inputs.connect()
			service.configureCheckout(project)
			state.inputs.openProject(project)
			state.inputs.selectThread(service.thread.id)
			try #require(await waitUntil
			{
				state.currentSnapshot.canSend
			})
			service.earlierReadsToSuspend = 2
			state.inputs.loadEarlierTurns()
			try #require(await waitUntil
			{
				service.suspendedEarlierReads[1] != nil
			})
			await state.inputs.connect()
			state.inputs.loadEarlierTurns()
			try #require(await waitUntil
			{
				service.suspendedEarlierReads[2] != nil
			})
			let stale = makeTurn(
				id: "stale",
				status: "completed",
				items: [[
					"id": "answer",
					"type": "agentMessage",
					"text": "Stale connection answer"
				]]
			)
			let current = makeTurn(
				id: "current",
				status: "completed",
				items: [[
					"id": "answer",
					"type": "agentMessage",
					"text": "Current connection answer"
				]]
			)
			if obsoleteFirst
			{
				service.suspendedEarlierReads.removeValue(forKey: 1)?.resume(returning: (
					[stale],
					nil
				))
				try await Task.sleep(for: .milliseconds(15))
				#expect(!state.currentSnapshot.canLoadEarlierTurns)
				#expect(state.currentSnapshot.entries.isEmpty)
			}
			service.suspendedEarlierReads.removeValue(forKey: 2)?.resume(returning: (
				[current],
				nil
			))
			try #require(
				await waitUntil
				{
					state.currentSnapshot.entries.first?.body == "Current connection answer"
				}
			)
			if !obsoleteFirst
			{
				service.suspendedEarlierReads.removeValue(forKey: 1)?.resume(returning: (
					[stale],
					nil
				))
				try await Task.sleep(for: .milliseconds(15))
			}
			#expect(state.currentSnapshot.entries.map(\.body) == ["Current connection answer"])
			#expect(state.currentSnapshot.reviewTurns.map(\.turnID) == ["current", "latest"])
		}
	}
}
