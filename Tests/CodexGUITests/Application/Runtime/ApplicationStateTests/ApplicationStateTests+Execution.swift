import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func stopBeforeThreadPreparationCancelsWithoutStartingTurn() async throws
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
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		service.suspendThreadStart = true
		state.inputs.updateDraft("Do not run this")
		let submission = try #require(state.inputs.send())
		try #require(await waitUntil
		{
			service.pendingThreadStart != nil
		})
		state.inputs.stop()
		#expect(state.currentSnapshot.activeExecutionState == .stopping)
		service.pendingThreadStart?.resume(returning: ThreadDetail(
			summary: service.thread,
			turns: [],
			nextTurnsCursor: nil
		))
		service.pendingThreadStart = nil
		_ = await submission.wait()
		#expect(service.turnStartCount == 0)
		#expect(service.interruptedTurnIDs.isEmpty)
		#expect(state.currentSnapshot.selectedThreadID == service.thread.id)
		#expect(state.currentSnapshot.statusMessage == "Request canceled before the task started.")
		#expect(state.currentSnapshot.draft == "Do not run this")
	}

	@Test func responseFailureAfterSynchronousTerminalEventPreservesOutcome() async throws
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
		let interaction = makeInteraction(
			id: "late-response",
			kind: .commandApproval
		)
		service.emit(.interaction(interaction))
		let completed = makeTurn(
			id: "turn-1",
			status: "interrupted"
		)
		service.savedTurns = [completed]
		service.beforeResponseReturns =
		{
			service.emit(.turnCompleted(
				threadId: service.thread.id,
				turn: completed
			))
		}
		service.responseError = AppServerError.requestTimedOut("request/respond")
		let response = try #require(state.inputs.respond(
			to: interaction,
			with: .approval(.accept)
		))
		_ = await response.wait()
		#expect(state.currentSnapshot.activeExecutionState == .stopped)
		#expect(state.currentSnapshot.statusMessage == "Agent interrupted.")
		#expect(state.currentSnapshot.pendingInteractions.isEmpty)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
	}

	@Test func olderCompletionReadCannotRestoreCommandAfterFreshRecoveryConfirmsExit() async throws
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
		let unresolved = makeTurn(
			id: "turn-1",
			status: "interrupted",
			items: [[
				"id": "command",
				"type": "commandExecution",
				"status": "inProgress",
				"command": "sleep 1",
			]]
		)
		service.suspendNextRead = true
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: unresolved
		))
		try #require(await waitUntil
		{
			service.pendingRead != nil
		})
		#expect(state.isTaskActive)
		let confirmed = makeTurn(
			id: "turn-1",
			status: "interrupted",
			items: [[
				"id": "command",
				"type": "commandExecution",
				"status": "completed",
				"command": "sleep 1",
				"exitCode": 0,
			]]
		)
		service.savedTurns = [confirmed]
		state.inputs.refreshThreads()
		try #require(await waitUntil
		{
			!state.isTaskActive && state.currentSnapshot.canSend
		})
		service.finishPendingRead(with: ThreadDetail(
			summary: service.thread,
			turns: [unresolved],
			nextTurnsCursor: nil
		))
		try #require(await waitUntil
		{
			state.pendingBackendOperationCount == 0
		})
		#expect(!state.isTaskActive)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
		try await state.store.awaitAcceptedPersistence()
		#expect(!WorkspaceLifecycleReducer.blocksCleanup(state.store.model))
		#expect(!state.beginWorkspaceCleanup())
		state.finishWorkspaceCleanup()
	}

	@Test func stopWaitsForTurnIDAndCompletionBeforeReportingStopped() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.suspendTurnStart = true
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
		#expect(await waitUntil
		{
			service.threadListCount > 0
		})
		state.inputs.updateDraft("Change a file")

		state.inputs.send()
		#expect(await waitUntil
		{
			service.pendingTurnStart != nil
		})
		state.inputs.stop()

		#expect(state.currentSnapshot.executionState == .stopping)
		#expect(service.interruptedTurnIDs.isEmpty)

		let turn = makeTurn(
			id: "turn-1",
			status: "inProgress"
		)
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: turn
		))
		#expect(await waitUntil
		{
			service.interruptedTurnIDs == ["turn-1"]
		})
		#expect(state.currentSnapshot.executionState == .stopping)

		service.finishTurnStart(with: turn)
		let listsBeforeCompletion = service.threadListCount
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "interrupted"
				)
			)
		)
		#expect(state.currentSnapshot.executionState == .stopped)
		#expect(state.currentSnapshot.statusMessage == "Agent interrupted.")
		#expect(service.interruptedTurnIDs == ["turn-1"])
		#expect(await waitUntil
		{
			service.threadListCount > listsBeforeCompletion
		})
		try await Task.sleep(for: .milliseconds(20))
		#expect(state.currentSnapshot.statusMessage == "Agent interrupted.")
		#expect(state.currentSnapshot.executionState == .stopped)
		#expect(state.currentSnapshot.canSend)
	}

	@Test func completedTurnAfterStopRequestKeepsCompletedOutcome() async throws
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
		state.inputs.updateDraft("Finish quickly")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		state.inputs.stop()
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		#expect(state.currentSnapshot.executionState == .completed)
		#expect(state.currentSnapshot.statusMessage == "Task completed before Stop took effect.")
	}

	@Test func multipleInteractionsRemainVisibleUntilEachIsResolved() async throws
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
		state.inputs.updateDraft("Run a task that asks for access")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 1
		})
		#expect(state.currentSnapshot.executionState == .running)

		let permission = makeInteraction(
			id: "permission",
			kind: .permissionApproval
		)
		let approval = makeInteraction(
			id: "approval",
			kind: .commandApproval
		)
		let question = makeInteraction(
			id: "question",
			kind: .question
		)
		service.emit(.interaction(permission))
		service.emit(.interaction(approval))
		service.emit(.interaction(question))
		#expect(
			state.currentSnapshot.pendingInteractions.map(\.id) == [
				"permission",
				"approval",
				"question",
			]
		)
		#expect(state.currentSnapshot.executionState == .awaitingAnswer)

		let approvalResponse = try #require(state.inputs.respond(
			to: approval,
			with: .approval(.decline)
		))
		_ = await approvalResponse.wait()
		#expect(state.currentSnapshot.pendingInteractions.map(\.id) == ["permission", "question"])
		#expect(state.currentSnapshot.executionState == .awaitingAnswer)

		service.emit(.interactionResolved(
			threadId: "thread-1",
			requestID: "question"
		))
		#expect(state.currentSnapshot.pendingInteractions.map(\.id) == ["permission"])
		#expect(state.currentSnapshot.executionState == .awaitingApproval)

		let permissionResponse = try #require(state.inputs.respond(
			to: permission,
			with: .permissions(
				granted: [:],
				scope: .turn
			)
		))
		_ = await permissionResponse.wait()
		#expect(state.currentSnapshot.pendingInteractions.isEmpty)
		#expect(state.currentSnapshot.executionState == .running)
		#expect(service.respondedRequestIDs == ["approval", "permission"])

		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		service.emit(.interactionResolved(
			threadId: "thread-1",
			requestID: "permission"
		))
		#expect(state.currentSnapshot.executionState == .completed)
	}

	@Test func browsingAnotherThreadPreservesOwnerEventsApprovalAndStopTarget() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: [
			"id": "thread-2",
			"name": "Other conversation",
			"preview": "Other conversation",
			"cwd": "/tmp",
			"status": ["type": "idle"],
		])!
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
		state.inputs.updateDraft("Make a change")
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
		state.inputs.updateDraft("Draft for B")
		service.emit(
			.agentMessageDelta(
				threadId: service.thread.id,
				turnId: "turn-1",
				itemId: "agent-1",
				text: "Working on A"
			)
		)
		service.emit(
			.diffUpdated(
				threadId: service.thread.id,
				turnId: "turn-1",
				diff: "diff --git a/a.txt b/a.txt\n+change\n"
			)
		)
		let approval = makeInteraction(
			id: "approval-a",
			kind: .commandApproval
		)
		service.emit(.interaction(approval))
		let ownerConversation = ConversationKey.thread(service.thread.id)
		let ownerExecution = state.store.model.execution(for: ownerConversation)
		let capturedOwner = try #require(ownerExecution.owner)
		#expect(ownerExecution.activeThreadID == service.thread.id)
		#expect(ownerExecution.state == .awaitingApproval)
		#expect(state.currentSnapshot.activeThreadID == nil)
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.currentSnapshot.executionState == .ready)
		#expect(state.currentSnapshot.pendingInteractions.isEmpty)
		#expect(state.currentSnapshot.entries.isEmpty)
		#expect(state.currentSnapshot.diff.isEmpty)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		#expect(service.turnStartCount == 1)

		state.inputs.setArchivedFilter(true)
		#expect(state.currentSnapshot.showingArchived)
		state.inputs.selectThread(service.thread.id)
		#expect(!state.currentSnapshot.showingArchived)

		#expect(state.currentSnapshot.entries.last?.body == "Working on A")
		#expect(state.currentSnapshot.diff.contains("a.txt"))
		#expect(state.currentSnapshot.pendingInteractions.map(\.id) == ["approval-a"])
		let approvalResponse = try #require(state.inputs.respond(
			to: approval,
			with: .approval(.decline)
		))
		_ = await approvalResponse.wait()
		#expect(service.respondedRequestIDs == ["approval-a"])

		state.inputs.selectThread("thread-2")
		#expect(state.inputs.stop() == nil)
		#expect(service.interruptedTurnIDs.isEmpty)
		state.inputs.stop(
			conversation: ownerConversation,
			capturedOwner: capturedOwner
		)
		#expect(await waitUntil
		{
			service.interruptedTurnIDs == ["turn-1"]
		})
		#expect(state.currentSnapshot.draft == "Draft for B")
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "interrupted"
				)
			)
		)
		#expect(state.currentSnapshot.activeExecutionState == nil)
		#expect(state.store.model.execution(for: ownerConversation).state == .stopped)
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.statusMessage == "Agent interrupted.")
		state.inputs.selectThread("thread-2")
		#expect(
			await waitUntil
			{
				state.currentSnapshot.selectedThreadID == "thread-2"
					&& state.currentSnapshot.statusMessage == nil
					&& state.currentSnapshot.canSend
			}
		)
		state.inputs.selectThread(service.thread.id)
		#expect(state.currentSnapshot.statusMessage == "Agent interrupted.")
	}

	@Test func staleEventsAndInteractionsCannotChangeNewTurn() async throws
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
		state.inputs.updateDraft("First")
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

		service.nextTurn = makeTurn(
			id: "turn-2",
			status: "inProgress"
		)
		state.inputs.updateDraft("Second")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.turnStartCount == 2
		})
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		let staleApproval = makeInteraction(
			id: "stale",
			kind: .commandApproval
		)
		service.emit(.interaction(staleApproval))
		service.emit(
			.agentMessageDelta(
				threadId: service.thread.id,
				turnId: "turn-1",
				itemId: "old",
				text: "old output"
			)
		)
		service.emit(
			.diffUpdated(
				threadId: service.thread.id,
				turnId: "turn-1",
				diff: "diff --git a/old b/old\n"
			)
		)
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "failed"
				)
			)
		)
		#expect(state.currentSnapshot.executionState == .running)
		#expect(state.currentSnapshot.pendingInteractions.isEmpty)
		#expect(!state.currentSnapshot.entries.contains(where:
			{
				$0.body == "old output"
			}))
		#expect(state.currentSnapshot.diff.isEmpty)
	}

	@Test func reconnectReconcilesOwnerWhileAnotherThreadIsVisible() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.otherThread = ThreadSummary(json: [
			"id": "thread-2",
			"name": "Other conversation",
			"cwd": project.path,
			"status": ["type": "idle"],
		])!
		service.turnsByThreadID["thread-2"] = []
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
		state.inputs.updateDraft("Do work")
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
		service.emitDisconnect("Backend exited.")
		service.savedTurns = [makeTurn(
			id: "turn-1",
			status: "completed"
		)]
		let readsBeforeReconnect = service.readThreadIDs.count
		await state.inputs.connect()
		#expect(service.readThreadIDs.dropFirst(readsBeforeReconnect).contains(service.thread.id))
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
				&& !state.store.model.execution(for: .thread(service.thread.id)).needsReconciliation
		})
		#expect(state.currentSnapshot.selectedThreadID == "thread-2")
		#expect(state.currentSnapshot.activeThreadID == nil)
		#expect(state.currentSnapshot.executionState == .ready)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
		#expect(!state.store.model.execution(for: .thread(service.thread.id)).hasUncertainRequest)
		#expect(state.currentSnapshot.canSend)
	}

	@Test func acceptedSteerAfterCompletionKeepsTerminalStatus() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.suspendSteer = true
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
		state.inputs.updateDraft("Change direction")
		state.inputs.steer("Change direction")
		#expect(await waitUntil
		{
			service.pendingSteer != nil
		})
		service.emit(
			.turnCompleted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "turn-1",
					status: "completed"
				)
			)
		)
		service.finishPendingSteer(acknowledgedTurnID: "turn-1")
		try #require(await waitUntil
		{
			state.currentSnapshot.draft.isEmpty
		})
		#expect(state.currentSnapshot.executionState == .completed)
		#expect(state.currentSnapshot.statusMessage == "Task completed.")
		#expect(service.steeredTurns.map(\.turnID) == ["turn-1"])
	}

	@Test func disconnectedTurnRemainsActiveUntilItsSavedOutcomeIsConfirmed() async throws
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
		service.onDisconnect?("Synthetic disconnect")
		#expect(state.isTaskActive)
		#expect(state.currentSnapshot.taskOutcomeUncertain)
		#expect(!state.beginWorkspaceCleanup())
		let coordinator = TaskWorkspaceCoordinator(sourceStore: state.store)
		let (_, approved) = await observedQuitOutcome(coordinator)
		{
			_ in true
		}
		#expect(!approved)
		if case .idle = coordinator.model.quit
		{
		}
		else
		{
			Issue.record("Disconnected uncertain turn must cancel ordinary quit.")
		}
		service.savedTurns = [makeTurn(
			id: "turn-1",
			status: "completed"
		)]
		await state.inputs.connect()
		#expect(!state.isTaskActive)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
	}

	@Test func obsoleteStopFailureCannotFailTheNextTurn() async throws
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
		service.suspendInterrupt = true
		state.inputs.stop()
		try #require(await waitUntil
		{
			service.pendingInterrupt != nil
		})
		let finished = makeTurn(
			id: "turn-1",
			status: "interrupted"
		)
		service.savedTurns = [finished]
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: finished
		))
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		service.nextTurn = makeTurn(
			id: "turn-2",
			status: "inProgress"
		)
		state.inputs.updateDraft("Another request")
		state.inputs.send()
		try #require(await waitUntil
		{
			service.turnStartCount == 2 && state.currentSnapshot.canSteer
		})
		service.pendingInterrupt?.resume(throwing: AppServerError.requestTimedOut("turn/interrupt"))
		service.pendingInterrupt = nil
		try await Task.sleep(for: .milliseconds(15))
		#expect(state.currentSnapshot.executionState == .running)
		#expect(state.currentSnapshot.canSteer)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
	}
}
