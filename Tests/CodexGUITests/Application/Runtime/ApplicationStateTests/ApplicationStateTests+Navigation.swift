import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test(arguments: [false, true])
	func selectingFirstProjectPreservesPendingSourceTransport(afterVersion: Bool) async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.suspendVersion = !afterVersion
		service.suspendConnection = afterVersion
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		#expect(state.currentSnapshot.projectPath == nil)
		let connection = Task
		{
			await state.inputs.connect()
		}
		try #require(await service.awaitReadiness
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
		try await awaitProjectContextLoad(state)
		#expect(service.connectionCount == 1)
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.backendDescription == "codex-cli 0.153.2 · Tested baseline")
	}

	@Test func selectionLoadBlocksSendAfterAnotherTaskCompletes() async throws
	{
		let project = try await makeProject()
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
		await awaitSubmissionReadiness(state)
		#expect(state.currentSnapshot.canSend)
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		#expect(await service.awaitReadiness
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let readsBeforeCompletion = service.readThreadCount
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		#expect(await service.awaitReadiness
		{
			service.readThreadCount == readsBeforeCompletion + 1
		})

		service.suspendNextRead = true
		state.inputs.selectThread("thread-2")
		#expect(await service.awaitReadiness
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
		await awaitSubmissionReadiness(state)
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.draft == "Work on B")
	}

	@Test func cleanReconnectRetriesSelectedHistoryAndClearsFinishedOwner() async throws
	{
		let project = try await makeProject()
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
		await awaitSubmissionReadiness(state)
		#expect(state.currentSnapshot.canSend)
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		#expect(await service.awaitReadiness
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let readsBeforeCompletion = service.readThreadCount
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		#expect(await service.awaitReadiness
		{
			service.readThreadCount == readsBeforeCompletion + 1
		})

		service.suspendNextRead = true
		let obsoleteRead = try #require(state.inputs.selectThread(other.id))
		#expect(await service.awaitReadiness
		{
			service.pendingRead != nil
		})
		// Cancellation finishes the handle before a suspended service returns.
		let obsoleteTasks = state.store.executionTasks(for: obsoleteRead.context)
		try #require(!obsoleteTasks.isEmpty)
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
		for task in obsoleteTasks
		{
			await task.value
		}
		#expect(state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.selectedThreadID == other.id)
		#expect(state.currentSnapshot.entries.map(\.body) == ["Current history in B"])
		#expect(state.currentSnapshot.reviewTurns.map(\.turnID) == [currentHistory.id])
		#expect(state.currentSnapshot.draft == "Draft for B")
	}

	@Test func bookmarkJumpLoadsOlderPageAndReportsMissingTarget() async throws
	{
		let project = try await makeProject()
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
		#expect(await awaitApplicationStateCondition(state)
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
		#expect(await awaitApplicationStateCondition(state)
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

	@Test(arguments: [nil, "idle", "active"] as [String?])
	func unselectedSearchHistoryCannotAdoptAnInProgressExecutionOwner(status: String?) async throws
	{
		let service = MockCodexService()
		var summaryJSON: [String: Any] = [
			"id": "thread-2",
			"cwd": "/tmp",
		]
		if let status
		{
			summaryJSON["status"] = ["type": status]
		}
		service.otherThread = ThreadSummary(json: summaryJSON)!
		service.turnsByThreadID["thread-2"] = [makeTurn(
			id: "remote-running",
			status: "inProgress",
			items: [["id": "answer", "type": "agentMessage", "text": "Unselected result"]]
		)]
		let store = contextStore(
			model: contextModel(),
			service: service
		)
		defer
		{
			store.shutdown()
		}
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
		let searchedExecution = store.model.execution(for: .thread("thread-2"))
		#expect(searchedExecution.owner == nil)
		#expect(searchedExecution.activeThreadID == nil)
		#expect(searchedExecution.activeTurnID == nil)
		#expect(searchedExecution.state == .ready)
		#expect(!searchedExecution.needsReconciliation)
		#expect(!searchedExecution.hasUncertainRequest)
		#expect(!store.model.hasActiveExecution)
		#expect(!WorkspaceLifecycleReducer.blocksCleanup(store.model))
	}

	@Test func messageSearchLoadsAnotherListedConversationAndUpdatesScope() async throws
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
		#expect(
			await awaitApplicationStateCondition(state)
			{
				state.currentSnapshot.entries.count == 1 && state.currentSnapshot.threads.count == 2
			}
		)
		state.inputs.searchMessages("needle")
		#expect(state.currentSnapshot.messageSearch?.scope.loadedThreadCount == 1)
		#expect(state.currentSnapshot.messageSearch?.scope.totalThreadCount == 2)
		let firstHit = MessageSearchHit(
			threadID: "thread-1",
			threadTitle: "Fixture conversation",
			turnID: "turn-a",
			itemID: "message-a",
			itemType: "userMessage",
			snippet: "needle one"
		)
		let secondHit = MessageSearchHit(
			threadID: "thread-2",
			threadTitle: "Other",
			turnID: "turn-b",
			itemID: "message-b",
			itemType: "agentMessage",
			snippet: "needle two"
		)
		try #require(await awaitApplicationStateCondition(state)
		{
			!state.currentSnapshot.searchLoading
		})
		#expect(state.currentSnapshot.messageSearch?.hits.count == 1)
		#expect(state.currentSnapshot.messageSearch?.hits == [firstHit])
		state.inputs.loadMoreSearchHistory()
		#expect(
			await awaitApplicationStateCondition(state)
			{
				state.currentSnapshot.messageSearch?.scope.loadedThreadCount == 2
					&& !state.currentSnapshot.searchLoading
			}
		)
		#expect(state.currentSnapshot.messageSearch?.hits.count == 2)
		#expect(state.currentSnapshot.messageSearch?.hits.sorted
		{
			$0.threadID < $1.threadID
		} == [firstHit, secondHit])
		#expect(service.readThreadIDs.contains("thread-2"))
		#expect(state.currentSnapshot.selectedThreadID == "thread-1")
		#expect(state.currentSnapshot.messageSearch?.scope.canLoadMore == false)
	}

	@Test func completionReadCannotPopulateAnotherProjectsSearchIndex() async throws
	{
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let (state, service, project) = try await makeRunningState(
			defaults: defaultsFixture.defaults
		)
		let otherProject = try await makeProject()
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
		try #require(await service.awaitReadiness
		{
			service.pendingRead != nil
		})
		let obsoleteRead = try #require(state.store.model.conversations.pendingReads[
			ConversationReadKey(
				purpose: .completion,
				threadID: service.thread.id
			)
		])
		let obsoleteTasks = state.store.executionTasks(for: obsoleteRead.context)
		try #require(!obsoleteTasks.isEmpty)
		service.configureCheckout(otherProject)
		state.inputs.openProject(otherProject)
		service.finishPendingRead(
			with: ThreadDetail(
				summary: service.thread,
				turns: [finished],
				nextTurnsCursor: nil
			)
		)
		// Inspect the new project only after the old service response was actually handled.
		for task in obsoleteTasks
		{
			await task.value
		}
		state.inputs.searchMessages("private old repository")
		#expect(state.currentSnapshot.projectPath == otherProject.path)
		#expect(state.currentSnapshot.messageSearch?.hits.isEmpty == true)
		#expect(state.currentSnapshot.navigationTargets.isEmpty)
	}

	@Test func lateHistoryPageCannotPopulateNewProjectOrConnection() async throws
	{
		for reconnect in [false, true]
		{
			let project = try await makeProject()
			let otherProject = try await makeProject()
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
			await awaitSubmissionReadiness(state)
			try #require(state.currentSnapshot.canSend)
			service.suspendEarlierRead = true
			state.inputs.loadEarlierTurns()
			try #require(await service.awaitReadiness
			{
				service.pendingEarlierRead != nil
			})
			let obsoletePage = try #require(
				state.store.model.conversations.historyLoads[service.thread.id]
			)
			let obsoleteTasks = state.store.executionTasks(for: obsoletePage.context)
			try #require(!obsoleteTasks.isEmpty)
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
			// A retired handle alone cannot prove that its late response has returned.
			for task in obsoleteTasks
			{
				await task.value
			}
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
