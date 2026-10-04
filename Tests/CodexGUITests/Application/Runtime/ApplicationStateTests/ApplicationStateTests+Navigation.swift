import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test(arguments: [false, true])
	func selectingFirstProjectPreservesPendingSourceTransport(afterVersion: Bool) async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.suspendVersion = !afterVersion
		service.suspendConnection = afterVersion
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		#expect(state.currentSnapshot.projectPath == nil)
		let connection = Task
		{
			await state.inputs.connect()
		}
		try #require(await waitUntil
		{
			afterVersion ? service.pendingConnection != nil : service.pendingVersion != nil
		})
		service.configureCheckout(project)
		state.inputs.openProject(project)
		#expect(state.currentSnapshot.projectPath == project.path)
		if afterVersion
		{
			service.pendingConnection?.resume()
			service.pendingConnection = nil
		}
		else
		{
			service.pendingVersion?.resume(returning: "codex-cli 0.153.2")
			service.pendingVersion = nil
		}
		await connection.value
		#expect(service.connectionCount == 1)
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.backendDescription == "codex-cli 0.153.2 · Tested baseline")
	}

	@Test func sharedPageUsesOneFiniteHandleForManualSearchAndJumpConsumers() async throws
	{
		for firstConsumer in ["manual", "search", "jump"]
		{
			let service = MockCodexService()
			service.suspendEarlierRead = true
			var model = WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp"
			))
			model.connection.isConnected = true
			model.execution.state = .ready
			model.conversations.selectedConversation = .thread(service.thread.id)
			let latest = makeTurn(
				id: "latest",
				status: "completed"
			)
			model.conversations.content[.thread(service.thread.id)] = ConversationContentModel(
				loadedTurns: [latest],
				hasLoadedHistory: true,
				nextTurnsCursor: "older"
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
			let scope = HistoryPageScope(
				projectPath: "/tmp",
				generation: 0,
				cursor: "older"
			)
			let first = HistoryLoadOperation(
				context: store.operationContext(threadID: service.thread.id),
				pageScope: scope,
				commandRevision: 0
			)
			store.dispatch(.conversations(.earlierTurnsRequested(first)))
			try #require(await waitUntil
			{
				service.pendingEarlierRead != nil
			})
			var handles: [String: WorkspaceOperationHandle] = [firstConsumer:
				try #require(store.operation(for: first.context))]
			for consumer in ["manual", "search", "jump"] where consumer != firstConsumer
			{
				let duplicate = HistoryLoadOperation(
					context: store.operationContext(threadID: service.thread.id),
					pageScope: scope,
					commandRevision: 0
				)
				store.dispatch(.conversations(.earlierTurnsRequested(duplicate)))
				let shared = try #require(store.model.conversations.historyLoads[service.thread.id])
				#expect(shared.context == first.context)
				let sharedHandle = try #require(store.operation(for: shared.context))
				handles[consumer] = sharedHandle
				#expect(store.operation(for: duplicate.context) == nil)
			}
			#expect(handles["manual"] === handles["search"])
			#expect(handles["manual"] === handles["jump"])
			#expect(store.runningOperationCount == 1)
			#expect(service.earlierReadCursors == ["older"])
			let older = makeTurn(
				id: "older",
				status: "completed"
			)
			service.pendingEarlierRead?.resume(returning: ([older, older, latest], nil))
			service.pendingEarlierRead = nil
			for handle in handles.values
			{
				#expect(await handle.wait() == .finished)
			}
			#expect(store.model.conversations.content[.thread(service.thread.id)]?.loadedTurns
				.map(\.id)
				== ["older", "latest"])
			#expect(service.earlierReadCursors == ["older"])
			#expect(store.model.conversations.historyLoads.isEmpty)
		}
	}

	@Test func suspendedHistoryAndPageReadsPreserveNewerStreamedText() async throws
	{
		for purpose in ([.selection, .search, nil] as [ConversationReadPurpose?])
		{
			let service = MockCodexService()
			service.suspendNextRead = purpose != nil
			service.suspendEarlierRead = purpose == nil
			var model = WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp"
			))
			model.connection.isConnected = true
			model.execution.state = .running
			model.conversations.selectedConversation = .thread(service.thread.id)
			model.execution.activeThreadID = service.thread.id
			model.execution.activeTurnID = "owner-turn"
			let owner = OperationContext(
				workspace: model.identity,
				generation: 0,
				requestID: UUID(),
				threadID: service.thread.id,
				turnID: "owner-turn"
			)
			model.execution.owner = ExecutionOwner(submission: owner)
			model.conversations.selectedConversation = .thread(service.thread.id)
			let original = makeTurn(
				id: "owner-turn",
				status: "inProgress",
				items: [[
					"id": "answer",
					"type": "agentMessage",
					"text": "original",
				]]
			)
			model.conversations.content[.thread(service.thread.id)] = ConversationContentModel(
				loadedTurns: [original],
				hasLoadedHistory: true,
				nextTurnsCursor: "older",
				entries: [ConversationEntry(
					id: "owner-turn:answer",
					kind: .agent,
					title: "Codex",
					body: "original"
				)]
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
			let context = store.operationContext(threadID: service.thread.id)
			if let purpose
			{
				store.dispatch(.conversations(.historyRequested(ConversationReadOperation(
					context: context,
					commandRevision: 0,
					purpose: purpose
				))))
				try #require(await waitUntil
				{
					service.pendingRead != nil
				})
			}
			else
			{
				store.dispatch(.conversations(.earlierTurnsRequested(HistoryLoadOperation(
					context: context,
					pageScope: HistoryPageScope(
						projectPath: "/tmp",
						generation: 0,
						cursor: "older"
					),
					commandRevision: 0
				))))
				try #require(await waitUntil
				{
					service.pendingEarlierRead != nil
				})
			}
			store.dispatch(.execution(.backendObserved(
				owner,
				.agentMessageDelta(
					threadId: service.thread.id,
					turnId: "owner-turn",
					itemId: "answer",
					text: "-live"
				)
			)))
			#expect(store.model.conversations.content[.thread(service.thread.id)]?.entries.first?
				.body
				== "original-live")
			#expect(store.model.execution.commandEventRevisions[service.thread.id, default: 0] == 0)
			if purpose != nil
			{
				service.finishPendingRead(with: ThreadDetail(
					summary: service.thread,
					turns: [original],
					nextTurnsCursor: "older"
				))
			}
			else
			{
				service.pendingEarlierRead?.resume(returning: ([original], nil))
				service.pendingEarlierRead = nil
			}
			#expect(await store.operation(for: context)?.wait() == .finished)
			#expect(store.model.conversations.content[.thread(service.thread.id)]?.entries.first?
				.body
				== "original-live")
			#expect(store.model.execution.commandEventRevisions[service.thread.id, default: 0] == 0)
		}
	}

	@Test func suspendedSelectionAndSearchReadsCannotReplaceNewerCommandExit() async throws
	{
		for purpose in [ConversationReadPurpose.selection, .search]
		{
			let service = MockCodexService()
			service.suspendNextRead = true
			var model = WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp"
			))
			model.connection.isConnected = true
			model.execution.state = .completed
			model.conversations.selectedConversation = .thread(service.thread.id)
			let pendingCommand = makeTurn(
				id: "owner",
				status: "completed",
				items: [[
					"id": "command",
					"type": "commandExecution",
					"status": "inProgress",
					"command": "sleep 1",
				]]
			)
			model.conversations.content[.thread(service.thread.id)] = ConversationContentModel(
				loadedTurns: [pendingCommand],
				hasLoadedHistory: true
			)
			model.execution.commandLifetime = TaskCommandLifetime(pending: [TaskCommandOwnership(
				threadID: service.thread.id,
				turnID: "owner",
				itemID: "command"
			)])
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
			let operation = ConversationReadOperation(
				context: store.operationContext(threadID: service.thread.id),
				commandRevision: 0,
				purpose: purpose
			)
			store.dispatch(.conversations(.historyRequested(operation)))
			try #require(await waitUntil
			{
				service.pendingRead != nil
			})
			let terminal = CodexItem(json: ["id": "command",
											"type": "commandExecution",
											"status": "completed",
											"command": "sleep 1",
											"exitCode": 0])!
			store.dispatch(.execution(.backendObserved(
				store.operationContext(threadID: service.thread.id),
				.itemCompleted(
					threadId: service.thread.id,
					turnId: "owner",
					item: terminal
				)
			)))
			#expect(!store.model.execution.commandLifetime.hasPendingCommands)
			service.finishPendingRead(with: ThreadDetail(
				summary: service.thread,
				turns: [pendingCommand],
				nextTurnsCursor: nil
			))
			#expect(await store.operation(for: operation.context)?.wait() == .finished)
			#expect(!store.model.execution.commandLifetime.hasPendingCommands)
			#expect(store.model.conversations.content[.thread(service.thread.id)]?.loadedTurns
				.first?.items.first?.status
				== "completed")
		}
	}

	@Test func suspendedPageCannotReviveCommandAfterLiveTerminalEvidence() async throws
	{
		let service = MockCodexService()
		service.suspendEarlierRead = true
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp"
		))
		model.connection.isConnected = true
		model.execution.state = .completed
		model.conversations.selectedConversation = .thread(service.thread.id)
		let pendingCommand = makeTurn(
			id: "owner",
			status: "completed",
			items: [[
				"id": "command",
				"type": "commandExecution",
				"status": "inProgress",
				"command": "sleep 1",
			]]
		)
		model.conversations.content[.thread(service.thread.id)] = ConversationContentModel(
			loadedTurns: [pendingCommand],
			hasLoadedHistory: true,
			nextTurnsCursor: "older"
		)
		model.execution.commandLifetime = TaskCommandLifetime(pending: [TaskCommandOwnership(
			threadID: service.thread.id,
			turnID: "owner",
			itemID: "command"
		)])
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
		let page = HistoryLoadOperation(
			context: store.operationContext(threadID: service.thread.id),
			pageScope: HistoryPageScope(
				projectPath: "/tmp",
				generation: 0,
				cursor: "older"
			),
			commandRevision: 0
		)
		store.dispatch(.conversations(.earlierTurnsRequested(page)))
		try #require(await waitUntil
		{
			service.pendingEarlierRead != nil
		})
		let terminal = CodexItem(json: ["id": "command",
										"type": "commandExecution",
										"status": "completed",
										"command": "sleep 1",
										"exitCode": 0])!
		store.dispatch(.execution(.backendObserved(
			store.operationContext(threadID: service.thread.id),
			.itemCompleted(
				threadId: service.thread.id,
				turnId: "owner",
				item: terminal
			)
		)))
		#expect(!store.model.execution.commandLifetime.hasPendingCommands)
		#expect(store.model.execution.commandEventRevisions[service.thread.id, default: 0] > 0)
		service.pendingEarlierRead?.resume(returning: ([pendingCommand], nil))
		service.pendingEarlierRead = nil
		#expect(await store.operation(for: page.context)?.wait() == .finished)
		#expect(!store.model.execution.commandLifetime.hasPendingCommands)
		#expect(store.model.conversations.content[.thread(service.thread.id)]?.loadedTurns.first?
			.items.first?.status
			== "completed")
	}

	@Test func staleReadFromEarlierSelectionCannotReplaceReturnedConversation() async throws
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
			"cwd": project.path,
		])!
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		service.suspendNextRead = true
		let obsoleteRead = try #require(state.inputs.selectThread(service.thread.id))
		#expect(await waitUntil
		{
			service.pendingRead != nil
		})
		state.inputs.selectThread("thread-2")
		service.savedTurns = [
			makeTurn(
				id: "new",
				status: "completed",
				items: [
					[
						"id": "message-new",
						"type": "agentMessage",
						"text": "new history",
					]
				]
			)
		]
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.entries.last?.body == "new history"
		})
		service.finishPendingRead(
			with: ThreadDetail(
				summary: service.thread,
				turns: [
					makeTurn(
						id: "old",
						status: "completed",
						items: [
							[
								"id": "message-old",
								"type": "agentMessage",
								"text": "old history",
							]
						]
					)
				],
				nextTurnsCursor: nil
			)
		)
		_ = await obsoleteRead.wait()
		#expect(state.currentSnapshot.entries.last?.body == "new history")
	}

	@Test func selectionLoadBlocksSendAfterAnotherTaskCompletes() async throws
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
			state.currentSnapshot.canSend
		})
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		#expect(await waitUntil
		{
			service.readThreadCount >= 2
		})

		service.suspendNextRead = true
		state.inputs.selectThread("thread-2")
		#expect(await waitUntil
		{
			service.pendingRead != nil
		})
		state.inputs.updateDraft("Work on B")
		#expect(!state.currentSnapshot.canSend)
		state.inputs.send()
		#expect(service.turnStartCount == 1)

		let other = ThreadSummary(json: [
			"id": "thread-2",
			"name": "Other",
			"preview": "Other",
			"cwd": "/tmp",
			"status": ["type": "idle"],
		])!
		service.finishPendingRead(
			with: ThreadDetail(
				summary: other,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		#expect(state.currentSnapshot.draft == "Work on B")
	}

	@Test func cleanReconnectRetriesSelectedHistoryAndClearsFinishedOwner() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let other = try #require(
			ThreadSummary(json: [
				"id": "thread-2",
				"name": "Other",
				"cwd": project.path,
			])
		)
		service.otherThread = other
		let currentHistory = makeTurn(
			id: "current-b",
			status: "completed",
			items: [["id": "answer-b", "type": "agentMessage", "text": "Current history in B"]]
		)
		service.turnsByThreadID[other.id] = [currentHistory]
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
			state.currentSnapshot.canSend
		})
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		#expect(await waitUntil
		{
			service.readThreadCount >= 2
		})

		service.suspendNextRead = true
		let obsoleteRead = try #require(state.inputs.selectThread(other.id))
		#expect(await waitUntil
		{
			service.pendingRead != nil
		})
		state.inputs.updateDraft("Draft for B")
		#expect(!state.currentSnapshot.canSend)
		await state.inputs.connect()
		#expect(state.currentSnapshot.selectedThreadID == "thread-2")
		#expect(state.currentSnapshot.activeThreadID == nil)
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.entries.map(\.body) == ["Current history in B"])
		let obsoleteHistory = makeTurn(
			id: "obsolete-b",
			status: "completed",
			items: [[
				"id": "old-answer-b",
				"type": "agentMessage",
				"text": "Obsolete history in B"
			]]
		)
		let detail = ThreadDetail(
			summary: other,
			turns: [obsoleteHistory],
			nextTurnsCursor: nil
		)
		service.finishPendingRead(with: detail)
		_ = await obsoleteRead.wait()
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.selectedThreadID == other.id)
		#expect(state.currentSnapshot.entries.map(\.body) == ["Current history in B"])
		#expect(state.currentSnapshot.reviewTurns.map(\.turnID) == [currentHistory.id])
		#expect(state.currentSnapshot.draft == "Draft for B")
	}

	@Test func bookmarkJumpLoadsOlderPageAndReportsMissingTarget() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.savedTurns = [
			makeTurn(
				id: "new",
				status: "completed",
				items: [
					["id": "new-message", "type": "agentMessage", "text": "Latest"]
				]
			)
		]
		service.readNextCursor = "older"
		service.earlierPages["older"] = (
			turns: [
				makeTurn(
					id: "old",
					status: "completed",
					items: [
						["id": "old-message", "type": "agentMessage", "text": "Earlier"]
					]
				)
			],
			nextCursor: nil
		)
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
			state.currentSnapshot.entries.count == 1
		})
		let bookmark = ConversationBookmark(
			threadID: service.thread.id,
			turnID: "old",
			itemID: "old-message",
			kind: .answer,
			label: "Earlier"
		)
		state.inputs.jumpToBookmark(bookmark)
		#expect(state.currentSnapshot.pendingJumpItemID == nil)
		#expect(await waitUntil
		{
			state.currentSnapshot.pendingJumpItemID == "old:old-message"
		})
		#expect(service.earlierReadCursors == ["older"])
		#expect(state.currentSnapshot.jumpError == nil)

		state.inputs.acknowledgeJump()
		let missing = ConversationBookmark(
			threadID: service.thread.id,
			turnID: "old",
			itemID: "missing",
			kind: .answer,
			label: "Deleted answer"
		)
		state.inputs.jumpToBookmark(missing)
		#expect(state.currentSnapshot.pendingJumpItemID == nil)
		#expect(state.currentSnapshot.jumpError?.contains("unavailable") == true)
	}

	@Test func unselectedSearchHistoryCannotAdoptAnInProgressExecutionOwner() async throws
	{
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: ["id": "thread-2", "cwd": "/tmp"])!
		service.turnsByThreadID["thread-2"] = [makeTurn(
			id: "remote-running",
			status: "inProgress",
			items: [["id": "answer", "type": "agentMessage", "text": "Unselected result"]]
		)]
		let store = contextStore(
			model: contextModel(),
			service: service
		)
		let operation = ConversationReadOperation(
			context: store.operationContext(threadID: "thread-2"),
			commandRevision: 0,
			purpose: .search
		)
		store.dispatch(.conversations(.historyRequested(operation)))
		let handle = try #require(store.operation(for: operation.context))
		#expect(await handle.wait() == .finished)
		#expect(store.model.conversations.content[.thread("thread-2")]?.loadedTurns
			.map(\.id) == ["remote-running"])
		#expect(store.model.conversations.selectedConversation == .thread("thread-1"))
		#expect(store.model.conversations.selectedConversation.threadID == "thread-1")
		#expect(store.model.execution.owner == nil)
		#expect(store.model.execution.activeThreadID == nil)
		#expect(store.model.execution.state == .ready)
	}

	@Test func messageSearchLoadsAnotherListedConversationAndUpdatesScope() async throws
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
						"id": "message-a",
						"type": "userMessage",
						"content": [["type": "inputText", "text": "needle one"]],
					]
				]
			)
		]
		service.turnsByThreadID["thread-2"] = [
			makeTurn(
				id: "turn-b",
				status: "completed",
				items: [
					["id": "message-b", "type": "agentMessage", "text": "needle two"]
				]
			)
		]
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(
			await waitUntil
			{
				state.currentSnapshot.entries.count == 1 && state.currentSnapshot.threads.count == 2
			}
		)
		state.inputs.searchMessages("needle")
		#expect(state.currentSnapshot.messageSearch?.scope.loadedThreadCount == 1)
		#expect(state.currentSnapshot.messageSearch?.scope.totalThreadCount == 2)
		try #require(await waitUntil
		{
			!state.currentSnapshot.searchLoading
		})
		#expect(state.currentSnapshot.messageSearch?.hits.count == 1)
		state.inputs.loadMoreSearchHistory()
		#expect(
			await waitUntil
			{
				state.currentSnapshot.messageSearch?.scope.loadedThreadCount == 2
					&& !state.currentSnapshot.searchLoading
			}
		)
		#expect(state.currentSnapshot.messageSearch?.hits.count == 2)
		#expect(state.currentSnapshot.messageSearch?.scope.canLoadMore == false)
	}

	@Test func completionReadCannotPopulateAnotherProjectsSearchIndex() async throws
	{
		let (state, service, project) = try await makeRunningState()
		let otherProject = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
			try? FileManager.default.removeItem(at: otherProject)
		}
		service.suspendNextRead = true
		let finished = makeTurn(
			id: "turn-1",
			status: "completed",
			items: [
				["id": "answer", "type": "agentMessage", "text": "private old repository message"]
			]
		)
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: finished
		))
		try #require(await waitUntil
		{
			service.pendingRead != nil
		})
		service.configureCheckout(otherProject)
		state.inputs.openProject(otherProject)
		service.finishPendingRead(
			with: ThreadDetail(
				summary: service.thread,
				turns: [finished],
				nextTurnsCursor: nil
			)
		)
		try await Task.sleep(for: .milliseconds(15))
		state.inputs.searchMessages("private old repository")
		#expect(state.currentSnapshot.projectPath == otherProject.path)
		#expect(state.currentSnapshot.messageSearch?.hits.isEmpty == true)
		#expect(state.currentSnapshot.navigationTargets.isEmpty)
	}

	@Test func repeatedEarlierPageClicksApplyOnlyOneCopy() async throws
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
			state.currentSnapshot.canLoadEarlierTurns
		})
		service.suspendEarlierRead = true
		state.inputs.loadEarlierTurns()
		state.inputs.loadEarlierTurns()
		try #require(await waitUntil
		{
			service.pendingEarlierRead != nil
		})
		#expect(service.earlierReadCursors == ["older"])
		#expect(!state.currentSnapshot.canLoadEarlierTurns)
		let older = makeTurn(
			id: "older-turn",
			status: "completed",
			items: [
				["id": "answer", "type": "agentMessage", "text": "older answer"]
			]
		)
		service.pendingEarlierRead?.resume(returning: ([older], nil))
		service.pendingEarlierRead = nil
		try #require(await waitUntil
		{
			state.currentSnapshot.entries.count == 1
		})
		#expect(state.currentSnapshot.reviewTurns.filter
		{
			$0.turnID == "older-turn"
		}.count == 1)
	}

	@Test func manualAndSearchPagingShareOneRequestInEitherStartOrder() async throws
	{
		for searchFirst in [false, true]
		{
			let project = try makeProject()
			defer
			{
				try? FileManager.default.removeItem(at: project)
			}
			let service = MockCodexService()
			service.readNextCursor = "older"
			let latest = makeTurn(
				id: "latest",
				status: "completed",
				items: [["id": "latest-answer", "type": "agentMessage", "text": "needle latest"]]
			)
			service.savedTurns = [latest]
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
			state.inputs.searchMessages("needle")
			service.suspendEarlierRead = true
			if searchFirst
			{
				state.inputs.loadMoreSearchHistory()
			}
			else
			{
				state.inputs.loadEarlierTurns()
			}
			try #require(await waitUntil
			{
				service.pendingEarlierRead != nil
			})
			if searchFirst
			{
				state.inputs.loadEarlierTurns()
			}
			else
			{
				state.inputs.loadMoreSearchHistory()
			}
			#expect(service.earlierReadCursors == ["older"])
			let older = makeTurn(
				id: "older-turn",
				status: "completed",
				items: [["id": "older-answer", "type": "agentMessage", "text": "needle older"]]
			)
			// Pages can overlap existing history and themselves.
			// Stable IDs own each turn once.
			service.pendingEarlierRead?.resume(returning: ([older, older, latest], nil))
			service.pendingEarlierRead = nil
			try #require(await waitUntil
			{
				state.currentSnapshot.reviewTurns.count == 2 && !state.currentSnapshot.searchLoading
			})
			#expect(state.currentSnapshot.reviewTurns.map(\.turnID) == ["older-turn", "latest"])
			#expect(service.earlierReadCursors == ["older"])
			#expect(state.currentSnapshot.entries.count == 2)
			#expect(state.currentSnapshot.messageSearch?.hits.count == 2)
			#expect(!state.currentSnapshot.canLoadEarlierTurns)
		}
	}

	@Test func manualAndJumpPagingShareOneRequestInEitherStartOrder() async throws
	{
		for jumpFirst in [false, true]
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
			let bookmark = ConversationBookmark(
				threadID: service.thread.id,
				turnID: "older-turn",
				itemID: "answer",
				kind: .answer,
				label: "Earlier answer"
			)
			service.suspendEarlierRead = true
			if jumpFirst
			{
				state.inputs.jumpToBookmark(bookmark)
			}
			else
			{
				state.inputs.loadEarlierTurns()
			}
			try #require(await waitUntil
			{
				service.pendingEarlierRead != nil
			})
			if jumpFirst
			{
				state.inputs.loadEarlierTurns()
			}
			else
			{
				state.inputs.jumpToBookmark(bookmark)
			}
			#expect(service.earlierReadCursors == ["older"])
			let older = makeTurn(
				id: "older-turn",
				status: "completed",
				items: [["id": "answer", "type": "agentMessage", "text": "Earlier answer"]]
			)
			service.pendingEarlierRead?.resume(returning: ([older], nil))
			service.pendingEarlierRead = nil
			try #require(await waitUntil
			{
				!state.currentSnapshot.jumpLoading
			})
			#expect(state.currentSnapshot.pendingJumpItemID == "older-turn:answer")
			#expect(state.currentSnapshot.jumpError == nil)
			#expect(service.earlierReadCursors == ["older"])
			#expect(state.currentSnapshot.entries.count == 1)
		}
	}

	@Test func lateHistoryPageCannotPopulateNewProjectOrConnection() async throws
	{
		for reconnect in [false, true]
		{
			let project = try makeProject()
			let otherProject = try makeProject()
			defer
			{
				try? FileManager.default.removeItem(at: project)
				try? FileManager.default.removeItem(at: otherProject)
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
			service.suspendEarlierRead = true
			state.inputs.loadEarlierTurns()
			try #require(await waitUntil
			{
				service.pendingEarlierRead != nil
			})
			if reconnect
			{
				await state.inputs.connect()
			}
			else
			{
				service.configureCheckout(otherProject)
				state.inputs.openProject(otherProject)
			}
			let obsolete = makeTurn(
				id: "obsolete",
				status: "completed",
				items: [["id": "answer", "type": "agentMessage", "text": "private stale page"]]
			)
			service.pendingEarlierRead?.resume(returning: ([obsolete], nil))
			service.pendingEarlierRead = nil
			try await Task.sleep(for: .milliseconds(15))
			#expect(!state.currentSnapshot.entries.contains
			{
				$0.body == "private stale page"
			})
			state.inputs.searchMessages("private stale page")
			#expect(state.currentSnapshot.messageSearch?.hits.isEmpty == true)
			#expect(state.currentSnapshot
				.projectPath == (reconnect ? project.path : otherProject.path))
		}
	}
}
