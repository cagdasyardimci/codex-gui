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
		var edited = false
		store.observe
		{
			_ in
			if !edited
			{
				edited = true
				store.dispatch(.review(.markerRequested(
					edit,
					identity: identity,
					reviewed: true
				)))
			}
		}
		store.dispatch(.review(.turnSelected(
			selection,
			conversation: .thread("thread"),
			turnID: "turn"
		)))
		#expect(await store.operation(for: selection)?.wait() == .finished)
		#expect(await store.operation(for: edit)?.wait() == .finished)
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

	@Test func offscreenReviewReadRetiresAndCachedMarkerSurvivesReturning() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.configureCheckout(project)
		let reported = makeTurn(
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
		)
		service.savedTurns = [reported]
		let key = ConversationKey.thread(service.thread.id)
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project.path
		))
		model.connection.generation = 1
		model.connection.isConnected = true
		model.conversations.selectedConversation = key
		model.conversations.content[key] = ConversationContentModel(
			loadedTurns: [reported],
			reviewSourceRevision: 1
		)
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let turn = try #require(ReviewReducer.selectedTurn(
			model,
			key
		))
		let identity = try #require(ReviewReducer.identities(turn).first)
		let markerDefaultsFixture = try IsolatedUserDefaultsFixture(prefix: "OffscreenReviewTests")
		defer
		{
			markerDefaultsFixture.cleanup()
		}
		let markers = ReviewMarkerStore(defaults: markerDefaultsFixture.defaults)
		markers.setReviewed(
			true,
			projectPath: project.path,
			reference: identity.reference,
			fingerprint: identity.fingerprint
		)
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let store = WorkspaceStateStore(
			model: model,
			service: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults),
			reviewMarkerStore: markers,
			persistence: WorkspacePersistenceScheduler(writeDraft:
				{
					_ in
				}),
			reducers: [WorkspaceFeatureComposition.reducer],
			reduceDomainEvent: ConversationReviewComposition
				.reduceDomainEvent
		)
		defer
		{
			store.shutdown()
		}
		let load = store.operationContext(threadID: service.thread.id)
		store.dispatch(.review(.turnSelected(
			load,
			conversation: key,
			turnID: "turn"
		)))
		#expect(store.model.review.conversations[key]?.pendingMarkerLoad != nil)
		// Both intents are synchronous, so navigation precedes the finite read callback.
		store.dispatch(.conversations(.newChatOpened(store.operationContext())))
		#expect(store.model.conversations.selectedConversation == .newChat)
		#expect(await store.operation(for: load)?.wait() == .finished)
		#expect(store.model.review.conversations[key]?.pendingMarkerLoad == nil)
		#expect(store.model.conversations.selectedConversation == .newChat)
		#expect(ReviewReducer.reviewedReferences(
			store.model,
			.newChat
		).isEmpty)
		#expect(ReviewReducer.reviewedReferences(
			store.model,
			key
		).contains(identity.reference))
		let returning = store.operationContext(threadID: service.thread.id)
		store.dispatch(.conversations(.selectionRequested(returning)))
		#expect(await store.operation(for: returning)?.wait() == .finished)
		#expect(store.model.conversations.selectedConversation == key)
		#expect(store.model.review.conversations[key]?.pendingMarkerLoad == nil)
		#expect(ReviewReducer.reviewedReferences(
			store.model,
			key
		).contains(identity.reference))
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

	@Test func aTurnWithoutChangesClearsThePreviousTurnDiff() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let firstTurn = makeTurn(
			id: "turn-1",
			status: "completed",
			items: [
				[
					"id": "change-1",
					"type": "fileChange",
					"status": "completed",
					"changes": [
						[
							"path": "README.md",
							"kind": "update",
							"diff": "@@ -1 +1 @@\n-before\n+after\n",
						]
					],
				]
			]
		)
		service.savedTurns = [firstTurn]
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
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			!state.currentSnapshot.diff.isEmpty
		})
		#expect(state.currentSnapshot.changedFiles.map(\.path) == ["README.md"])

		service.nextTurn = makeTurn(
			id: "turn-2",
			status: "inProgress"
		)
		state.inputs.updateDraft("Explain the result without editing files")
		state.inputs.send()
		#expect(state.currentSnapshot.diff.isEmpty)
		#expect(state.currentSnapshot.changedFiles.isEmpty)
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})

		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let completedTurn = makeTurn(
			id: "turn-2",
			status: "completed"
		)
		service.savedTurns = [firstTurn, completedTurn]
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: completedTurn
		))
		#expect(state.currentSnapshot.executionState == .completed)
		#expect(state.currentSnapshot.diff.isEmpty)
		#expect(state.currentSnapshot.changedFiles.isEmpty)
	}

	@Test func proposedAndDeniedChangesStayOutOfReviewIncludingSavedHistory() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
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
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})

		func fileItem(
			_ id: String,
			path: String,
			status: String
		) -> [String: Any]
		{
			[
				"id": id,
				"type": "fileChange",
				"status": status,
				"changes": [["path": path, "kind": ["type": "add"], "diff": "new contents\n"]],
			]
		}
		let proposed = try #require(
			CodexItem(json: fileItem(
				"denied",
				path: "denied.py",
				status: "inProgress"
			))
		)
		service.emit(.itemStarted(
			threadId: service.thread.id,
			turnId: "turn-1",
			item: proposed
		))
		service.emit(
			.fileChangeUpdated(
				threadId: service.thread.id,
				turnId: "turn-1",
				itemId: proposed.id,
				changes: proposed.changes
			)
		)
		#expect(state.currentSnapshot.changedFiles.isEmpty)
		#expect(state.currentSnapshot.diff.isEmpty)

		let acceptedJSON = fileItem(
			"accepted",
			path: "accepted.py",
			status: "completed"
		)
		let accepted = try #require(CodexItem(json: acceptedJSON))
		service.emit(.itemCompleted(
			threadId: service.thread.id,
			turnId: "turn-1",
			item: accepted
		))
		let declinedJSON = fileItem(
			"denied",
			path: "denied.py",
			status: "declined"
		)
		let declined = try #require(CodexItem(json: declinedJSON))
		service.emit(.itemCompleted(
			threadId: service.thread.id,
			turnId: "turn-1",
			item: declined
		))
		#expect(state.currentSnapshot.changedFiles.map(\.path) == ["accepted.py"])
		#expect(!state.currentSnapshot.diff.contains("denied.py"))
		#expect(state.currentSnapshot.entries.last?.title == "File changes · completed")

		service.savedTurns = [
			makeTurn(
				id: "turn-1",
				status: "completed",
				items: [acceptedJSON, declinedJSON]
			)
		]
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			service.readThreadCount == 2 && state.currentSnapshot.canSend
		})
		#expect(state.currentSnapshot.changedFiles.map(\.path) == ["accepted.py"])
		#expect(state.currentSnapshot.changedFiles.first?.status == "add")
		#expect(!state.currentSnapshot.diff.contains("denied.py"))
		#expect(state.currentSnapshot.entries.last?.title == "File changes · declined")
	}

	@Test func historicalReviewKeepsTurnOriginAndInvalidatesChangedMarkers() async throws
	{
		let project = try makeProject()
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
		#expect(await waitUntil
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
			await waitUntil
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
		let project = try makeProject()
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
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.reviewTurns.count == 1
		})
		#expect(state.currentSnapshot.reviewTurns[0].validations[0].currency == .uncertain)

		service.nextTurn = makeTurn(
			id: "turn-b",
			status: "inProgress"
		)
		state.inputs.updateDraft("Update a file")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.selectThread("thread-2")
		#expect(await waitUntil
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
		let project = try makeProject()
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
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.selectedReview != nil
		})
		state.inputs.updateDraft("Start task")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.selectThread("thread-2")
		#expect(
			await waitUntil
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
		#expect(await waitUntil
		{
			service.steeredTurns.count == 1
		})
		#expect(service.steeredTurns[0].threadID == service.thread.id)
		#expect(service.steeredTurns[0].turnID == service.nextTurn.id)
		#expect(service.steeredTurns[0].text.contains("Origin turn: source-turn"))
	}

	@Test func backgroundCompletionKeepsVisibleConversationAndReviewSelection() async throws
	{
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let (state, service, project) = try await makeRunningState(
			defaults: defaultsFixture.defaults
		)
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let other = try #require(
			ThreadSummary(json: [
				"id": "thread-2",
				"name": "Other",
				"cwd": project.path,
			])
		)
		service.otherThread = other
		service.turnsByThreadID[other.id] = [
			makeTurn(
				id: "other-turn",
				status: "completed",
				items: [[
					"id": "other-answer",
					"type": "agentMessage",
					"text": "Visible other answer"
				]]
			)
		]
		state.inputs.selectThread(other.id)
		try #require(
			await waitUntil
			{
				state.currentSnapshot.entries.first?.body == "Visible other answer"
			}
		)
		state.inputs.selectReviewTurn("other-turn")
		state.inputs.updateDraft("Other draft")
		let ownerTurn = makeTurn(
			id: service.nextTurn.id,
			status: "completed",
			items: [[
				"id": "owner-answer",
				"type": "agentMessage",
				"text": "Background owner answer"
			]]
		)
		service.savedTurns = [ownerTurn]
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: ownerTurn
		))
		try #require(await waitUntil
		{
			state.currentSnapshot.navigationTargets.isEmpty
		})
		try await Task.sleep(for: .milliseconds(15))
		#expect(state.currentSnapshot.selectedThreadID == other.id)
		#expect(state.currentSnapshot.selectedReviewTurnID == "other-turn")
		#expect(state.currentSnapshot.entries.first?.body == "Visible other answer")
		#expect(state.currentSnapshot.draft == "Other draft")
		state.inputs.selectThread(service.thread.id)
		try #require(
			await waitUntil
			{
				state.currentSnapshot.entries.first?.body == "Background owner answer"
			}
		)
		#expect(state.currentSnapshot.selectedReview?.threadID == service.thread.id)
	}
}
