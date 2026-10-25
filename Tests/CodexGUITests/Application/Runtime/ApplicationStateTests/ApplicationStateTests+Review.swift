import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func reviewMarkerReservationPreservesReentrantEditsAndReloadsCapturedCheckout(
	) async throws
	{
		let markerDefaultsFixture = try IsolatedUserDefaultsFixture(prefix: "ReviewRuntimeTests")
		defer
		{
			markerDefaultsFixture.cleanup()
		}
		let markers = ReviewMarkerStore(defaults: markerDefaultsFixture.defaults)
		let service = MockCodexService()
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/review-runtime"
		))
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [makeTurn(
				id: "turn",
				status: "completed",
				items: [[
					"id": "change",
					"type": "fileChange",
					"status": "completed",
					"changes": [["path": "A.swift",
									"kind": "update",
									"diff": "@@ -1 +1 @@\n-old\n+new\n"]],
				]]
			)],
			reviewSourceRevision: 1
		)
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let turn = try #require(ReviewReducer.selectedTurn(
			model,
			.thread("thread")
		))
		let identity = try #require(ReviewReducer.identities(turn).first)
		let unchangedHunk = try #require(ReviewReducer.identities(turn).last)
		markers.setReviewed(
			true,
			projectPath: "/tmp/review-runtime",
			reference: unchangedHunk.reference,
			fingerprint: unchangedHunk.fingerprint
		)

		let store = WorkspaceStateStore(
			model: model,
			service: service,
			reviewMarkerStore: markers,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [ReviewReducer.reducer]
		)
		defer
		{
			store.shutdown()
		}
		let selection = store.operationContext(threadID: "thread")
		let edit = store.operationContext(threadID: "thread")
		var armed = false
		var edited = false
		var reservedRead: ReviewMarkerReadOperation?
		let observation = store.observe
		{
			published in
			guard armed, !edited,
					let pending = published.review.conversations[.thread("thread")]?
					.pendingMarkerLoad,
					pending.context.requestID == selection.requestID
			else
			{
				return
			}
			reservedRead = pending
			edited = true
			store.dispatch(.review(.markerRequested(
				edit,
				identity: identity,
				reviewed: true
			)))
		}
		defer
		{
			store.removeObserver(observation)
		}
		#expect(!edited)
		// Observe registers synchronously; only the selection publication may trigger the edit.
		armed = true
		store.dispatch(.review(.turnSelected(
			selection,
			conversation: .thread("thread"),
			turnID: "turn"
		)))
		try #require(edited)
		let capturedRead = try #require(reservedRead)
		#expect(capturedRead.markerRevision == 0)
		#expect(store.model.review.conversations[.thread("thread")]?.markerRevision == 1)
		let selectionHandle = try #require(store.operation(for: selection))
		let editHandle = try #require(store.operation(for: edit))
		#expect(await selectionHandle.wait() == .finished)
		#expect(await editHandle.wait() == .finished)
		#expect(ReviewReducer.reviewedReferences(
			store.model,
			.thread("thread")
		)
		.contains(identity.reference))

		#expect(ReviewReducer.reviewedReferences(
			store.model,
			.thread("thread")
		)
		.contains(unchangedHunk.reference))
		#expect(markers.isReviewed(
			projectPath: "/tmp/review-runtime",
			reference: identity.reference,
			fingerprint: identity.fingerprint
		))
		// A new store/session hydrates the existing unchanged marker schema through its effect.
		model.identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/review-runtime"
		)
		model.review = ReviewModel()
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let restored = WorkspaceStateStore(
			model: model,
			service: MockCodexService(),
			reviewMarkerStore: markers,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [ReviewReducer.reducer]
		)
		defer
		{
			restored.shutdown()
		}
		let load = restored.operationContext(threadID: "thread")
		restored.dispatch(.review(.turnSelected(
			load,
			conversation: .thread("thread"),
			turnID: "turn"
		)))
		#expect(await restored.operation(for: load)?.wait() == .finished)
		#expect(ReviewReducer.reviewedReferences(
			restored.model,
			.thread("thread")
		)
		.contains(identity.reference))
		#expect(!markers.isReviewed(
			projectPath: "/tmp/other-checkout",
			reference: identity.reference,
			fingerprint: identity.fingerprint
		))
	}

	@Test func ownerStreamingAndTerminalReviewStayCanonicalWhileAnotherThreadIsViewed() async throws
	{
		let service = MockCodexService()
		let viewed = "viewed-thread"
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp"
		))
		model.connection.isConnected = true
		model.conversations.selectedConversation = .thread(service.thread.id)
		model.execution.state = .running
		let owner = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID(),
			threadID: service.thread.id,
			turnID: "owner-turn"
		)
		model.execution.owner = ExecutionOwner(submission: owner)
		model.execution.activeThreadID = service.thread.id
		model.execution.activeTurnID = "owner-turn"
		model.conversations.selectedConversation = .thread(viewed)
		model.conversations.content[.thread(service.thread.id)] = ConversationContentModel(
			loadedTurns: [makeTurn(
				id: "owner-turn",
				status: "inProgress"
			)],
			hasLoadedHistory: true
		)
		let historical = makeTurn(
			id: "historical",
			status: "completed",
			items: [[
				"id": "viewed-answer",
				"type": "agentMessage",
				"text": "viewed content",
			]]
		)
		model.conversations.content[.thread(viewed)] = ConversationContentModel(
			loadedTurns: [historical],
			hasLoadedHistory: true,
			entries: [ConversationEntry(
				id: "historical:viewed-answer",
				kind: .agent,
				title: "Codex",
				body: "viewed content"
			)]
		)
		model.review.conversations[.thread(viewed)] = ConversationReviewModel(
			turns: [ReviewTurn(
				threadID: viewed,
				turnID: "historical",
				files: [],
				validations: [],
				codeStateID: "historical-state",
				hasUnknownEarlierHistory: false
			)],
			selectedTurnID: "historical"
		)
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [WorkspaceFeatureComposition.reducer],
			reduceDomainEvent: ConversationReviewComposition.reduceDomainEvent
		)
		defer
		{
			store.shutdown()
		}
		var observedBodies: [String] = []
		store.observe
		{
			model in
			if let body = model.conversations.content[.thread(service.thread.id)]?.entries
				.first(where:
					{
						$0.kind == .agent
					})?.body
			{
				observedBodies.append(body)
			}
			#expect(model.conversations.selectedConversation == .thread(viewed))
			#expect(model.review.conversations[.thread(viewed)]?.selectedTurnID == "historical")
		}
		for fragment in ["one", "two", "three"]
		{
			store.dispatch(.execution(.backendObserved(
				owner,
				.agentMessageDelta(
					threadId: service.thread.id,
					turnId: "owner-turn",
					itemId: "answer",
					text: fragment
				)
			)))
		}
		#expect(observedBodies == ["one", "onetwo", "onetwothree"])
		#expect(store.model.conversations.content[.thread(viewed)]?.entries.first?
			.body == "viewed content")
		let terminal = makeTurn(
			id: "owner-turn",
			status: "completed",
			items: [
				["id": "answer", "type": "agentMessage", "text": "onetwothree"],
				["id": "change", "type": "fileChange", "status": "completed", "changes": [[
					"path": "Owner.swift",
					"kind": "update",
					"diff": "@@ -1 +1 @@\n-old\n+new\n",
				]]],
			]
		)
		service.savedTurns = [terminal]
		store.dispatch(.execution(.backendObserved(
			owner,
			.turnCompleted(
				threadId: service.thread.id,
				turn: terminal
			)
		)))
		#expect(store.model.conversations.content[.thread(service.thread.id)]?.loadedTurns.last?
			.status == "completed")
		#expect(store.model.review.conversations[.thread(service.thread.id)]?.turns.last?
			.threadID == service.thread.id)
		#expect(store.model.review.conversations[.thread(service.thread.id)]?.turns.last?
			.turnID == "owner-turn")
		#expect(store.model.review.conversations[.thread(service.thread.id)]?.turns.last?.files
			.first?.path == "Owner.swift")
		_ = await store.operation(for: owner)?.wait()
		#expect(store.model.review.conversations[.thread(viewed)]?.selectedTurnID == "historical")
		#expect(store.model.conversations.content[.thread(viewed)]?.loadedTurns
			.map(\.id) == ["historical"])
	}

	@Test func historicalReviewKeepsTurnOriginAndInvalidatesChangedMarkers() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let firstChange: [String: Any] = [
			"id": "change-a",
			"type": "fileChange",
			"status": "completed",
			"changes": [
				[
					"path": "Sources/A.swift",
					"kind": "update",
					"diff": "@@ -1 +1 @@\n-old\n+new\n",
				]
			],
		]
		let secondChange: [String: Any] = [
			"id": "change-b",
			"type": "fileChange",
			"status": "completed",
			"changes": [
				[
					"path": "Sources/B.swift",
					"kind": "update",
					"diff": "@@ -1 +1 @@\n-before\n+after\n",
				]
			],
		]
		service.savedTurns = [
			makeTurn(
				id: "turn-a",
				status: "completed",
				items: [firstChange]
			),
			makeTurn(
				id: "turn-b",
				status: "completed",
				items: [secondChange]
			),
		]
		let markerDefaultsFixture = try IsolatedUserDefaultsFixture(prefix: "ReviewStateTests")
		defer
		{
			markerDefaultsFixture.cleanup()
		}
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults),
			reviewMarkerStore: ReviewMarkerStore(defaults: markerDefaultsFixture.defaults)
		)
		defer
		{
			state.shutdown()
		}
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await awaitApplicationStateCondition(state)
		{
			state.currentSnapshot.reviewTurns.count == 2
		})
		state.inputs.selectReviewTurn("turn-a")
		let review = try #require(state.currentSnapshot.selectedReview)
		let file = try #require(review.files.first)
		let hunk = try #require(file.hunks.first)
		#expect(review.threadID == service.thread.id)
		#expect(review.turnID == "turn-a")
		#expect(file.path == "Sources/A.swift")
		#expect(state.currentSnapshot.selectedReviewTurnID == "turn-a")

		let reference = ReviewReference(
			threadID: review.threadID,
			turnID: review.turnID,
			file: file,
			hunk: hunk
		)
		state.inputs.setReviewed(
			true,
			reference: reference
		)
		#expect(state.currentSnapshot.reviewedReferences.contains(reference))
		state.inputs.prepareChangeRequest(
			kind: .revision,
			reference: reference
		)
		#expect(state.currentSnapshot.draft.contains("Origin thread: \(service.thread.id)"))
		#expect(state.currentSnapshot.draft.contains("Origin turn: turn-a"))
		#expect(state.currentSnapshot.draft.contains("Sources/A.swift"))
		#expect(state.currentSnapshot.draft.contains(hunk.id))

		let revisedChange: [String: Any] = [
			"id": "change-a",
			"type": "fileChange",
			"status": "completed",
			"changes": [
				[
					"path": "Sources/A.swift",
					"kind": "update",
					"diff": "@@ -1 +1 @@\n-old\n+different\n",
				]
			],
		]
		service.savedTurns[0] = makeTurn(
			id: "turn-a",
			status: "completed",
			items: [revisedChange]
		)
		state.inputs.selectThread(service.thread.id)
		#expect(
			await awaitApplicationStateCondition(state)
			{
				state.currentSnapshot.selectedReview?.files.first?.diff
					.contains("different") == true
			}
		)
		#expect(!state.currentSnapshot.reviewedReferences.contains(reference))
	}

	@Test func reportedLiveEditMakesEarlierValidationOutdatedWhileViewingAnotherThread()
		async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: [
			"id": "thread-2",
			"name": "Other",
			"preview": "Other",
			"cwd": "/tmp",
			"status": ["type": "idle"],
		])
		service.savedTurns = [
			makeTurn(
				id: "turn-a",
				status: "completed",
				items: [
					[
						"id": "check",
						"type": "commandExecution",
						"status": "completed",
						"command": "swift test",
						"aggregatedOutput": "passed",
						"exitCode": 0,
					]
				]
			)
		]
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try await awaitProjectContextLoad(state)
		let selection = try #require(state.inputs.selectThread(service.thread.id))
		try #require(await selection.wait() == .finished)
		#expect(await awaitApplicationStateCondition(state)
		{
			state.currentSnapshot.reviewTurns.count == 1
		})
		#expect(state.currentSnapshot.reviewTurns[0].validations[0].currency == .uncertain)

		service.nextTurn = makeTurn(
			id: "turn-b",
			status: "inProgress"
		)
		state.inputs.updateDraft("Update a file")
		let submission = try #require(state.inputs.send())
		try #require(await submission.wait() == .finished)
		#expect(service.turnStartCount == 1)
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.selectThread("thread-2")
		#expect(await awaitApplicationStateCondition(state)
		{
			state.currentSnapshot.selectedThreadID == "thread-2"
		})
		let change = try #require(
			CodexItem(json: [
				"id": "change-b",
				"type": "fileChange",
				"status": "completed",
				"changes": [
					[
						"path": "Sources/A.swift",
						"kind": "update",
						"diff": "@@ -1 +1 @@\n-old\n+new\n",
					]
				],
			])
		)
		service.emit(.itemCompleted(
			threadId: service.thread.id,
			turnId: "turn-b",
			item: change
		))
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.reviewTurns[0].validations[0].currency == .outdated)
	}

	@Test func reviewRequestSteersOnlyTheViewedOwnerWithSourceIdentity() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: [
			"id": "thread-2",
			"name": "Other",
			"preview": "Other",
			"cwd": "/tmp",
			"status": ["type": "idle"],
		])
		service.savedTurns = [
			makeTurn(
				id: "source-turn",
				status: "completed",
				items: [
					[
						"id": "change",
						"type": "fileChange",
						"status": "completed",
						"changes": [
							[
								"path": "Sources/A.swift",
								"kind": "update",
								"diff": "@@ -1 +1 @@\n-old\n+new\n",
							]
						],
					]
				]
			)
		]
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try await awaitProjectContextLoad(state)
		let selection = try #require(state.inputs.selectThread(service.thread.id))
		try #require(await selection.wait() == .finished)
		#expect(await awaitApplicationStateCondition(state)
		{
			state.currentSnapshot.selectedReview != nil
		})
		state.inputs.updateDraft("Start task")
		let submission = try #require(state.inputs.send())
		try #require(await submission.wait() == .finished)
		#expect(service.turnStartCount == 1)
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.selectThread("thread-2")
		#expect(
			await awaitApplicationStateCondition(state)
			{
				state.currentSnapshot.selectedThreadID == "thread-2"
					&& state.currentSnapshot.selectedReview != nil
			}
		)
		let otherReview = try #require(state.currentSnapshot.selectedReview)
		let otherFile = try #require(otherReview.files.first)
		let otherReference = ReviewReference(
			threadID: otherReview.threadID,
			turnID: otherReview.turnID,
			file: otherFile,
			hunk: nil
		)
		state.inputs.prepareChangeRequest(
			kind: .ask,
			reference: otherReference
		)
		state.inputs.steer(state.currentSnapshot.draft)
		#expect(service.steeredTurns.isEmpty)

		state.inputs.selectThread(service.thread.id)
		let ownerReview = try #require(state.currentSnapshot.selectedReview)
		let ownerFile = try #require(ownerReview.files.first)
		let ownerReference = ReviewReference(
			threadID: ownerReview.threadID,
			turnID: ownerReview.turnID,
			file: ownerFile,
			hunk: nil
		)
		state.inputs.prepareChangeRequest(
			kind: .revision,
			reference: ownerReference
		)
		let sourceBoundDraft = state.currentSnapshot.draft
		#expect(sourceBoundDraft.contains("Origin thread: \(service.thread.id)"))
		#expect(sourceBoundDraft.contains("Origin turn: source-turn"))
		state.inputs.steer(sourceBoundDraft)
		#expect(await service.awaitReadiness
		{
			service.steeredTurns.count == 1
		})
		#expect(service.steeredTurns[0].threadID == service.thread.id)
		#expect(service.steeredTurns[0].turnID == service.nextTurn.id)
		#expect(service.steeredTurns[0].text.contains("Origin turn: source-turn"))
	}

}
