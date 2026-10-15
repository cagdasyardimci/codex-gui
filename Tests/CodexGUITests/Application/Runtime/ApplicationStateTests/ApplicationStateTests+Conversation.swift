import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func eachSequentialTerminalTurnRefreshesItsOwnHistory() async throws
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
		for number in 1 ... 2
		{
			if number == 2
			{
				service.nextTurn = makeTurn(
					id: "turn-2",
					status: "inProgress"
				)
				state.inputs.updateDraft("Second request")
				let submission = try #require(state.inputs.send())
				_ = await submission.wait()
			}
			let readsBefore = service.readThreadCount
			let completed = makeTurn(
				id: "turn-\(number)",
				status: "completed"
			)
			service.savedTurns.append(completed)
			service.emit(.turnCompleted(
				threadId: service.thread.id,
				turn: completed
			))
			try #require(await waitUntil
			{
				service.readThreadCount == readsBefore + 1
			})
			try #require(await waitUntil
			{
				state.currentSnapshot.canSend
			})
		}
	}

	@Test func streamingReducesImmediatelyAndCoalescesVisiblePublication() async throws
	{
		let publicationGate = PublicationGate()
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let (state, service, project) = try await makeRunningState(
			defaults: defaultsFixture.defaults,
			publicationWait:
			{
				await publicationGate.wait()
			}
		)
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		try #require(await waitUntil
		{
			state.currentSnapshot.draft.isEmpty
		})
		var publications = 0
		state.onChange =
		{
			_ in
			publications += 1
		}
		#expect(publications == 1)
		publications = 0
		for text in ["one", "two", "three"]
		{
			service.emit(.agentMessageDelta(
				threadId: service.thread.id,
				turnId: "turn-1",
				itemId: "agent",
				text: text
			))
		}
		#expect(state.currentSnapshot.entries.contains
		{
			$0.body == "onetwothree"
		})
		#expect(publications == 0)
		try #require(await waitUntil
		{
			publicationGate.isWaiting
		})
		#expect(publications == 0)
		publicationGate.release()
		try #require(await waitUntil
		{
			publications == 1
		})
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: makeTurn(
				id: "turn-1",
				status: "completed"
			)
		))
		#expect(publications == 2)
	}

	@Test func readingAnotherThreadsHistoryWhileOwnerCommandStreamsKeepsBothContents() async throws
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
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		state.inputs.updateDraft("Work on A")
		state.inputs.send()
		try #require(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let command = try #require(
			CodexItem(json: [
				"id": "command-a",
				"type": "commandExecution",
				"status": "inProgress",
				"command": "check-a",
				"cwd": project.path,
			])
		)
		service.emit(
			.itemStarted(
				threadId: service.thread.id,
				turnId: service.nextTurn.id,
				item: command
			)
		)
		service.suspendNextRead = true
		state.inputs.selectThread(other.id)
		try #require(await waitUntil
		{
			service.pendingRead != nil
		})
		service.emit(
			.commandOutputDelta(
				threadId: service.thread.id,
				turnId: service.nextTurn.id,
				itemId: command.id,
				text: "A continues working"
			)
		)
		let history = makeTurn(
			id: "b-history",
			status: "completed",
			items: [
				["id": "b-answer", "type": "agentMessage", "text": "Earlier decision in B"]
			]
		)
		service.pendingRead?.resume(
			returning: ThreadDetail(
				summary: other,
				turns: [history],
				nextTurnsCursor: nil
			)
		)
		service.pendingRead = nil
		#expect(
			await waitUntil
			{
				state.currentSnapshot.entries.contains
				{
					$0.body == "Earlier decision in B"
				}
			}
		)
		#expect(state.currentSnapshot.activeThreadID == nil)
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.store.model.execution(for: .thread(service.thread.id)).activeThreadID
			== service.thread.id)
		#expect(state.store.model.execution(for: .thread(service.thread.id)).activeTurnID
			== service.nextTurn.id)
		#expect(!state.currentSnapshot.entries.contains
		{
			$0.body.contains("A continues working")
		})
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.entries.contains
		{
			$0.body.contains("A continues working")
		})
	}

	@Test func uncertainSteerKeepsRunningTaskStoppableAcrossHistoryRefresh() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.steerError = AppServerError.requestTimedOut("turn/steer")
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
		state.inputs.updateDraft("Initial request")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.updateDraft("Redirect")
		state.inputs.steer("Redirect")
		#expect(
			await waitUntil
			{
				state.currentSnapshot.statusMessage?.contains("outcome is uncertain") == true
			}
		)
		let conversation = ConversationKey.thread(service.thread.id)
		let owner = try #require(state.store.model.execution(for: conversation).owner)
		state.inputs.selectThread("thread-2")
		state.inputs.refreshThreads()
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.store.model.execution(for: conversation).state == .running)
		state.inputs.stop(
			conversation: conversation,
			capturedOwner: owner
		)
		#expect(await waitUntil
		{
			service.interruptedTurnIDs == ["turn-1"]
		})
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.store.model.execution(for: conversation).state == .stopping)
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.activeExecutionState == .stopping)
		#expect(state.currentSnapshot.draft == "Redirect")
	}

	@Test func terminalCommandHistoryClearsLiveCleanupBarrier() async throws
	{
		for useRefresh in [false, true]
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
			let running = makeTurn(
				id: "turn-1",
				status: "interrupted",
				items: [
					[
						"id": "command",
						"type": "commandExecution",
						"status": "inProgress",
						"command": "sleep 1",
					]
				]
			)
			let finished = makeTurn(
				id: "turn-1",
				status: "interrupted",
				items: [
					[
						"id": "command",
						"type": "commandExecution",
						"status": "completed",
						"command": "sleep 1",
						"exitCode": 0,
					]
				]
			)
			service.savedTurns = useRefresh ? [running] : [finished]
			service.emit(.turnCompleted(
				threadId: service.thread.id,
				turn: running
			))
			#expect(state.isTaskActive)
			#expect(!state.beginWorkspaceCleanup())
			if useRefresh
			{
				try #require(await waitUntil
				{
					service.readThreadCount >= 2
				})
				service.savedTurns = [finished]
				state.inputs.refreshThreads()
			}
			try #require(await waitUntil
			{
				!state.isTaskActive
			})
			#expect(!state.currentSnapshot.taskOutcomeUncertain)
			try await state.store.awaitAcceptedPersistence()
			#expect(!WorkspaceLifecycleReducer.blocksCleanup(state.store.model))
			#expect(!state.beginWorkspaceCleanup())
			state.finishWorkspaceCleanup()
		}
	}
}
