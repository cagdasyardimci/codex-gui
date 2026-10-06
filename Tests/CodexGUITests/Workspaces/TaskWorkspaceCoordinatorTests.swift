import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite(
	"Independent task execution",
	.serialized
)
struct TaskWorkspaceCoordinatorTests
{
	@Test func ordinaryChatsStopTogetherAndPublishEachCompletion() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		try await startOrdinaryChats(fixture)
		var finishedThreads: Set<String> = []
		fixture.coordinator.onTaskSnapshot =
		{
			presentation in
			if presentation.executionState == .stopped, let threadID = presentation.activeThreadID
			{
				finishedThreads.insert(threadID)
			}
		}
		var completionCount = 0
		fixture.coordinator.onAllTasksFinished =
		{
			completionCount += 1
		}
		fixture.sourceState.inputs.newChat()
		#expect(fixture.sourceState.currentSnapshot.selectedThreadID == nil)
		#expect(fixture.coordinator.isTaskActive)
		let originalIdentity = fixture.sourceState.store.model.identity
		let otherSource = fixture.root.appendingPathComponent("other-source")
		try FileManager.default.createDirectory(
			at: otherSource.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		fixture.coordinator.openProject(otherSource)
		#expect(fixture.sourceState.store.model.identity == originalIdentity)
		fixture.coordinator.stopAll()
		try #require(await waitUntil
		{
			fixture.sourceService.interruptionRequests.count == 2
		})
		#expect(Set(fixture.sourceService.interruptionRequests.map(\.threadID))
			== Set(["source", "second"]))
		fixture.sourceService.complete(
			threadID: "source",
			status: "interrupted"
		)
		#expect(fixture.coordinator.isTaskActive)
		#expect(finishedThreads == ["source"])
		#expect(completionCount == 0)
		fixture.sourceService.complete(
			threadID: "second",
			status: "interrupted"
		)
		try #require(await waitUntil
		{
			completionCount == 1
		})
		#expect(!fixture.coordinator.isTaskActive)
		#expect(finishedThreads == ["source", "second"])
		#expect(fixture.sourceState.store.model.lifecycle.quitReservation == nil)
	}

	@Test func ordinaryChatsQuitWaitsForBothRemoteOutcomes() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		try await startOrdinaryChats(fixture)
		var quitApproved: Bool?
		fixture.coordinator.onQuitCompleted =
		{
			_, approved in quitApproved = approved
		}
		let request = fixture.coordinator.requestQuit()
		fixture.coordinator.confirmQuit(
			request,
			approved: true
		)
		try #require(await waitUntil
		{
			fixture.sourceService.interruptionRequests.count == 2
		})
		fixture.sourceService.complete(
			threadID: "second",
			status: "interrupted"
		)
		#expect(quitApproved == nil)
		#expect(fixture.coordinator.isTaskActive)
		fixture.sourceService.complete(
			threadID: "source",
			status: "interrupted"
		)
		try #require(await waitUntil
		{
			quitApproved != nil
		})
		#expect(quitApproved == true)
		#expect(fixture.sourceState.store.model.lifecycle.quitReservation?.requestID
			== request.requestID)
	}

	@Test func reconnectReconcilesEveryOrdinaryChatWithoutResending() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		try await startOrdinaryChats(fixture)
		fixture.sourceService.onDisconnect?("Synthetic transport loss.")
		#expect(fixture.sourceState.store.model.hasUncertainExecutionRequest)
		fixture.sourceService.savedTurns = [fixture.sourceService.finishedTurn(status: "completed")]
		let second = try #require(fixture.sourceService.additionalThreads["second"])
		fixture.sourceService.additionalThreads["second"] = ThreadDetail(
			summary: second.summary,
			turns: [fixture.sourceService.finishedTurn(status: "interrupted")],
			nextTurnsCursor: nil
		)
		fixture.sourceService.readThreadIDs.removeAll()
		await fixture.sourceState.inputs.connect()
		try #require(await waitUntil
		{
			!fixture.sourceState.store.model.hasUncertainExecutionRequest
				&& !fixture.sourceState.store.model.hasExecutionReconciliation
		})
		#expect(Set(fixture.sourceService.readThreadIDs) == Set(["source", "second"]))
		#expect(fixture.sourceService.turnRequests.count == 2)
		#expect(fixture.sourceService.interruptionRequests.isEmpty)
		#expect(!fixture.coordinator.isTaskActive)
	}

	@Test func agentOnlyRelaunchReadsEveryPersistedOwnerBeforeStopping() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		fixture.sourceService.observeTurnStart =
		{
			threadID in
			#expect(
				fixture.storage.activeExecutionThreadIDs(for: fixture.source).contains(threadID)
			)
		}
		try await startOrdinaryChats(fixture)
		#expect(
			fixture.storage.activeExecutionThreadIDs(for: fixture.source) == ["second", "source"]
		)
		let service = WorkspaceCodexService(
			directory: fixture.source,
			threadID: "source"
		)
		service.savedTurns = [service.turn]
		service.additionalThreads["second"] = ThreadDetail(
			summary: try #require(ThreadSummary(json: [
				"id": "second",
				"cwd": fixture.source.path,
				"status": ["type": "idle"],
			])),
			turns: [service.turn],
			nextTurnsCursor: nil
		)
		for threadID in ["source", "second"]
		{
			service.readThreadDetails[threadID] = ThreadDetail(
				summary: try #require(ThreadSummary(json: [
					"id": threadID,
					"cwd": fixture.source.path,
					"status": ["type": "active", "activeFlags": []],
				])),
				turns: [service.turn],
				nextTurnsCursor: nil
			)
		}
		let recovered = WorkspaceTestFixture(
			server: service,
			storage: fixture.storage
		)
		let coordinator = TaskWorkspaceCoordinator(
			sourceStore: recovered.store,
			manager: fixture.manager
		)
		defer
		{
			coordinator.shutdown()
		}
		await recovered.inputs.connect()
		try #require(await waitUntil
		{
			Set(service.readThreadIDs) == Set(["source", "second"])
				&& recovered.store.model.execution(for: .thread("source")).activeTurnID != nil
				&& recovered.store.model.execution(for: .thread("second")).activeTurnID != nil
		})
		#expect(service.turnRequests.isEmpty)
		#expect(coordinator.isTaskActive)
		coordinator.stopAll()
		try #require(await waitUntil
		{
			service.interruptionRequests.count == 2
		})
		service.complete(
			threadID: "source",
			status: "interrupted"
		)
		#expect(coordinator.isTaskActive)
		service.complete(
			threadID: "second",
			status: "interrupted"
		)
		try #require(await waitUntil
		{
			!coordinator.isTaskActive
		})
		#expect(fixture.storage.activeExecutionThreadIDs(for: fixture.source).isEmpty)
	}

	@Test func activeUnselectedThreadSummaryDiscoversRemoteAgentOwner() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		fixture.sourceService.additionalThreads["second"] = ThreadDetail(
			summary: try #require(ThreadSummary(json: [
				"id": "second",
				"cwd": fixture.source.path,
				"status": ["type": "active", "activeFlags": []],
			])),
			turns: [fixture.sourceService.turn],
			nextTurnsCursor: nil
		)
		await fixture.sourceState.inputs.connect()
		try #require(await waitUntil
		{
			fixture.sourceState.store.model.execution(for: .thread("second")).activeTurnID != nil
		})
		#expect(fixture.sourceService.readThreadIDs.contains("second"))
		#expect(fixture.sourceService.turnRequests.isEmpty)
		#expect(fixture.coordinator.isTaskActive)
		#expect(fixture.sourceState.currentSnapshot.selectedThreadID == nil)
		#expect(fixture.storage.activeExecutionThreadIDs(for: fixture.source) == ["second"])
	}

	@Test func relaunchReconcilesEveryPersistedOrdinaryCommandOwner() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		let commands = ["source", "second"].map
		{
			TaskCommandOwnership(
				threadID: $0,
				turnID: "turn-one",
				itemID: "approved-command"
			)
		}
		fixture.storage.savePendingCommands(
			Set(commands),
			for: fixture.source
		)
		let service = WorkspaceCodexService(
			directory: fixture.source,
			threadID: "source"
		)
		service.additionalThreads["second"] = ThreadDetail(
			summary: try #require(ThreadSummary(json: [
				"id": "second",
				"cwd": fixture.source.path,
			])),
			turns: [service.finishedTurn(status: "interrupted")],
			nextTurnsCursor: nil
		)
		service.savedTurns = [service.finishedTurn(status: "interrupted")]
		let recovered = WorkspaceTestFixture(
			server: service,
			storage: fixture.storage
		)
		let coordinator = TaskWorkspaceCoordinator(
			sourceStore: recovered.store,
			manager: fixture.manager
		)
		defer
		{
			coordinator.shutdown()
		}
		await recovered.inputs.connect()
		try #require(await waitUntil
		{
			Set(service.readThreadIDs) == Set(["source", "second"])
		})
		#expect(recovered.store.model.pendingCommandOwnership.count == 2)
		#expect(coordinator.isTaskActive)
		#expect(recovered.store.model.blocksExecutionCleanup)
		#expect(service.turnRequests.isEmpty)
		let completed = try command(
			status: "completed",
			cwd: fixture.source.path
		)
		service.emit(.itemCompleted(
			threadId: "source",
			turnId: "turn-one",
			item: completed
		))
		#expect(coordinator.isTaskActive)
		#expect(recovered.store.model.pendingCommandOwnership.map(\.threadID) == ["second"])
		service.emit(.itemCompleted(
			threadId: "second",
			turnId: "turn-one",
			item: completed
		))
		try #require(await waitUntil
		{
			!coordinator.isTaskActive
		})
		try await recovered.store.awaitAcceptedPersistence()
		#expect(fixture.storage.pendingCommands(for: fixture.source).isEmpty)
	}

	@Test func ordinaryChatsAndManagedCommandKeepCheckoutProtectedDuringStopAll() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let managed = try await fixture.createTask("Managed")
		managed.state.inputs.updateDraft("Run command")
		managed.state.inputs.send()
		try #require(await waitUntil
		{
			managed.service.turnRequests.count == 1
		})
		let running = try command(
			status: "inProgress",
			cwd: managed.workspace.checkoutPath
		)
		managed.service.emit(.itemStarted(
			threadId: managed.service.thread.id,
			turnId: managed.service.turn.id,
			item: running
		))
		fixture.coordinator.selectSourceCheckout()
		try await startOrdinaryChats(fixture)
		fixture.coordinator.stopAll()
		try #require(await waitUntil
		{
			fixture.sourceService.interruptionRequests.count == 2
				&& managed.service.interruptionRequests.count == 1
		})
		fixture.sourceService.complete(
			threadID: "source",
			status: "interrupted"
		)
		fixture.sourceService.complete(
			threadID: "second",
			status: "interrupted"
		)
		managed.service.savedTurns = [CodexTurn(
			id: managed.service.turn.id,
			status: "interrupted",
			items: [running],
			error: nil
		)]
		managed.service.emit(.turnCompleted(
			threadId: managed.service.thread.id,
			turn: managed.service.savedTurns[0]
		))
		#expect(fixture.coordinator.isTaskActive)
		await fixture.coordinator.removeCheckout(id: managed.workspace.id)
		#expect(FileManager.default.fileExists(atPath: managed.workspace.checkoutPath))
		let completed = try command(
			status: "completed",
			cwd: managed.workspace.checkoutPath
		)
		managed.service.emit(.itemCompleted(
			threadId: managed.service.thread.id,
			turnId: managed.service.turn.id,
			item: completed
		))
		try #require(await waitUntil
		{
			!fixture.coordinator.isTaskActive
				&& managed.state.store.model.lifecycle.quitReservation == nil
		})
		await fixture.coordinator.removeCheckout(id: managed.workspace.id)
		#expect(!FileManager.default.fileExists(atPath: managed.workspace.checkoutPath))
	}

	private func startOrdinaryChats(_ fixture: TaskExecutionFixture) async throws
	{
		fixture.sourceService.additionalThreads["second"] = ThreadDetail(
			summary: try #require(ThreadSummary(json: [
				"id": "second",
				"cwd": fixture.source.path,
			])),
			turns: [],
			nextTurnsCursor: nil
		)
		if !fixture.sourceState.store.model.connection.isConnected
		{
			await fixture.sourceState.inputs.connect()
		}
		for threadID in ["source", "second"]
		{
			fixture.sourceState.inputs.selectThread(threadID)
			try #require(await waitUntil
			{
				fixture.sourceState.currentSnapshot.selectedThreadID == threadID
					&& fixture.sourceState.currentSnapshot.canSend
			})
			fixture.sourceState.inputs.updateDraft("Run \(threadID)")
			fixture.sourceState.inputs.send()
			try #require(await waitUntil
			{
				let execution = fixture.sourceState.store.model.execution(for: .thread(threadID))
				return execution.state == .running && execution.activeTurnID != nil
					&& fixture.sourceService.turnRequests.contains
					{
						$0.threadID == threadID
					}
			})
		}
	}

	@Test func sourceOpeningPublishesMatchingCoordinatorAndSnapshotCheckout() throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		let next = fixture.root.appendingPathComponent(
			"next-source",
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: next.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		let coordinator = fixture.coordinator
		var observedPaths: [String?] = []
		coordinator.onChange =
		{
			snapshot in
			guard case .source = coordinator.model.selectedOwner
			else
			{
				return
			}
			#expect(coordinator.sourceProjectURL?.path == snapshot.projectPath)
			observedPaths.append(snapshot.projectPath)
		}
		coordinator.openProject(next)
		#expect(coordinator.sourceProjectURL?.path == next.path)
		#expect(coordinator.currentSnapshot.projectPath == next.path)
		#expect(observedPaths.last == next.path)
		let acceptedOwner = coordinator.captureSelectedOwner()
		coordinator.openProject(fixture.root.appendingPathComponent("missing-source"))
		#expect(coordinator.captureSelectedOwner() == acceptedOwner)
		#expect(coordinator.sourceProjectURL?.path == next.path)
		#expect(coordinator.currentSnapshot.projectPath == next.path)
		#expect(observedPaths.last == next.path)
	}

	@Test func interruptedAgentWaitsForApprovedCommandBeforeCleanupAndQuit() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		alpha.state.inputs.updateDraft("Run approved command")
		alpha.state.inputs.send()
		try #require(await waitUntil
		{
			alpha.state.currentSnapshot.draft.isEmpty
		})
		let running = try command(
			status: "inProgress",
			cwd: alpha.workspace.checkoutPath
		)
		alpha.service.emit(
			.itemStarted(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				item: running
			)
		)
		var finishCount = 0
		fixture.coordinator.onAllTasksFinished =
		{
			finishCount += 1
		}
		fixture.coordinator.stopAll()
		let interrupted = CodexTurn(
			id: alpha.service.turn.id,
			status: "interrupted",
			items: [running],
			error: nil
		)
		alpha.service.savedTurns = [interrupted]
		alpha.service.emit(.turnCompleted(
			threadId: alpha.service.thread.id,
			turn: interrupted
		))
		#expect(alpha.state.currentSnapshot.executionState == .stopping)
		#expect(fixture.coordinator.isTaskActive)
		#expect(!alpha.state.currentSnapshot.canSend)
		#expect(finishCount == 0)
		await fixture.coordinator.removeCheckout(id: alpha.workspace.id)
		#expect(FileManager.default.fileExists(atPath: alpha.workspace.checkoutPath))
		#expect(!fixture.coordinator.currentSnapshot.taskWorkspaces[0].canRemoveCheckout)

		let completed = try command(
			status: "completed",
			cwd: alpha.workspace.checkoutPath
		)
		alpha.service.emit(
			.itemCompleted(
				threadId: "another-owner",
				turnId: alpha.service.turn.id,
				item: completed
			)
		)
		#expect(fixture.coordinator.isTaskActive)
		alpha.service.emit(
			.commandOutputDelta(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				itemId: running.id,
				text: "A_DONE\n"
			)
		)
		try #require(
			await waitUntil
			{
				alpha.state.currentSnapshot.entries.contains
				{
					$0.body.contains("A_DONE")
				}
			}
		)
		alpha.service.emit(
			.itemCompleted(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				item: completed
			)
		)
		#expect(!fixture.coordinator.isTaskActive)
		#expect(alpha.state.currentSnapshot.executionState == .stopped)
		await waitForQuitCallback(fixture.coordinator)
		{
			finishCount == 1
		}
		#expect(finishCount == 1)
		#expect(alpha.state.currentSnapshot.selectedReview?.validations.first?.exitCode == 0)
		#expect(alpha.state.currentSnapshot.selectedReview?.validations.first?.output == "A_DONE\n")
		await fixture.coordinator.removeCheckout(id: alpha.workspace.id)
		#expect(!FileManager.default.fileExists(atPath: alpha.workspace.checkoutPath))
	}

	@Test func unresolvedCommandSurvivesDisconnectAndRelaunchWithMissingHistoryItem() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		alpha.state.inputs.updateDraft("Run command")
		alpha.state.inputs.send()
		try #require(await waitUntil
		{
			alpha.state.currentSnapshot.draft.isEmpty
		})
		let running = try command(
			status: "inProgress",
			cwd: alpha.workspace.checkoutPath
		)
		alpha.service.emit(
			.itemStarted(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				item: running
			)
		)
		alpha.service.complete(status: "interrupted")
		alpha.service.onDisconnect?("Synthetic connection lost")
		var canceledQuit = 0
		fixture.coordinator.onStopAllFailed =
		{
			canceledQuit += 1
		}
		fixture.coordinator.stopAll()
		await waitForQuitCallback(fixture.coordinator)
		{
			canceledQuit == 1
		}
		#expect(canceledQuit == 1)
		#expect(alpha.state.currentSnapshot.taskOutcomeUncertain)
		let workspace = try #require(await fixture.manager.activeCheckout(id: alpha.workspace.id))
		let recoveredService = WorkspaceCodexService(
			directory: URL(fileURLWithPath: workspace.checkoutPath),
			threadID: alpha.service.thread.id
		)
		recoveredService.savedTurns = [alpha.service.finishedTurn(status: "interrupted")]
		let recoveryCoordinator = fixture
			.restoredCoordinator(services: [workspace.id: recoveredService])
		defer
		{
			recoveryCoordinator.shutdown()
		}
		await recoveryCoordinator.sourceStore.inputs.connect()
		await recoveryCoordinator.reloadWorkspaces()
		await recoveryCoordinator.selectWorkspace(workspace.id)
		let recovered = WorkspaceTestFixture(store: recoveryCoordinator.selectedStore)
		#expect(recovered.isTaskActive)
		#expect(recovered.currentSnapshot.taskOutcomeUncertain)
		#expect(!recovered.beginWorkspaceCleanup())
		#expect(!recovered.currentSnapshot.canSend)
		var choseStopAndQuit = false
		let (_, quitApproved) = await observedQuitOutcome(recoveryCoordinator)
		{
			_ in
			choseStopAndQuit = true
			return true
		}
		#expect(choseStopAndQuit)
		#expect(!quitApproved)
		if case .idle = recoveryCoordinator.model.quit
		{
		}
		else
		{
			Issue.record("Uncertain command must cancel ordinary quit.")
		}
		#expect(recovered.currentSnapshot.taskOutcomeUncertain)
		let completed = try command(
			status: "completed",
			cwd: workspace.checkoutPath
		)
		recoveredService.savedTurns = [
			CodexTurn(
				id: alpha.service.turn.id,
				status: "interrupted",
				items: [completed],
				error: nil
			)
		]
		recovered.inputs.refreshThreads()
		try #require(await waitUntil
		{
			!recovered.currentSnapshot.taskOutcomeUncertain
		})
		#expect(!recovered.isTaskActive)
		#expect(recovered.beginWorkspaceCleanup())
		recovered.finishWorkspaceCleanup()
	}

	@Test func terminalSavedTurnWithRunningCommandReconstructsCleanupBarrier() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let workspace = try await fixture.manager.bindThread(
			id: alpha.workspace.id,
			threadID: alpha.service.thread.id
		)
		let service = WorkspaceCodexService(
			directory: URL(fileURLWithPath: workspace.checkoutPath),
			threadID: alpha.service.thread.id
		)
		service.savedTurns = [
			CodexTurn(
				id: service.turn.id,
				status: "interrupted",
				items: [try command(
					status: "inProgress",
					cwd: workspace.checkoutPath
				)],
				error: nil
			)
		]
		let state = WorkspaceTestFixture(
			server: service,
			storage: fixture.storage,
			taskWorkspace: workspace,
			taskWorkspaceManager: fixture.manager
		)
		defer
		{
			state.shutdown()
		}
		await state.inputs.connect()
		#expect(state.isTaskActive)
		#expect(state.currentSnapshot.taskOutcomeUncertain)
		#expect(!state.beginWorkspaceCleanup())
		service.emit(
			.itemCompleted(
				threadId: service.thread.id,
				turnId: service.turn.id,
				item: try command(
					status: "completed",
					cwd: workspace.checkoutPath
				)
			)
		)
		#expect(!state.isTaskActive)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
		#expect(state.currentSnapshot.selectedReview?.validations.first?.exitCode == 0)
	}

	@Test func olderRefreshAndSelectionReadsCannotUndoConfirmedCommandExit() async throws
	{
		for selectConversation in [false, true]
		{
			let fixture = try TaskExecutionFixture()
			defer
			{
				fixture.remove()
			}
			await fixture.sourceState.inputs.connect()
			let alpha = try await fixture.createTask("Alpha")
			let workspace = try await fixture.manager.bindThread(
				id: alpha.workspace.id,
				threadID: alpha.service.thread.id
			)
			let service = WorkspaceCodexService(
				directory: URL(fileURLWithPath: workspace.checkoutPath),
				threadID: alpha.service.thread.id
			)
			let running = try command(
				status: "inProgress",
				cwd: workspace.checkoutPath
			)
			service.savedTurns = [
				CodexTurn(
					id: service.turn.id,
					status: "interrupted",
					items: [running],
					error: nil
				)
			]
			let state = WorkspaceTestFixture(
				server: service,
				storage: fixture.storage,
				taskWorkspace: workspace,
				taskWorkspaceManager: fixture.manager
			)
			defer
			{
				state.shutdown()
			}
			await state.inputs.connect()
			if selectConversation
			{
				service.savedTurns = [
					CodexTurn(
						id: service.turn.id,
						status: "interrupted",
						items: [],
						error: nil
					)
				]
			}
			service.suspendNextRead = true
			if selectConversation
			{
				state.inputs.selectThread(service.thread.id)
			}
			else
			{
				state.inputs.refreshThreads()
			}
			try #require(await waitUntil
			{
				service.pendingRead != nil
			})
			service.emit(
				.itemCompleted(
					threadId: service.thread.id,
					turnId: service.turn.id,
					item: try command(
						status: "completed",
						cwd: workspace.checkoutPath
					)
				)
			)
			#expect(!state.isTaskActive)
			service.pendingRead?.resume(returning: service.detail())
			service.pendingRead = nil
			try await Task.sleep(for: .milliseconds(15))
			#expect(!state.isTaskActive)
			#expect(!state.currentSnapshot.taskOutcomeUncertain)
			#expect(state.currentSnapshot.selectedReview?.validations.first?.exitCode == 0)
			#expect(state.currentSnapshot.entries.contains
			{
				$0.body.contains("A_DONE")
			})
			#expect(
				fixture.storage.pendingCommands(for: URL(fileURLWithPath: workspace.checkoutPath))
					.isEmpty
			)
		}
	}

	private func command(
		status: String,
		cwd: String
	) throws -> CodexItem
	{
		try #require(
			CodexItem(json: [
				"id": "approved-command",
				"type": "commandExecution",
				"status": status,
				"command": "python3 delayed_write.py",
				"cwd": cwd,
				"aggregatedOutput": status == "completed" ? "A_DONE\n" : "",
				"exitCode": status == "completed" ? 0 : NSNull(),
			])
		)
	}

	@Test func fatalAgentErrorCancelsQuitAndWaitsForItsCommandsOwnOutcome() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		alpha.state.inputs.updateDraft("Run command")
		alpha.state.inputs.send()
		try #require(await waitUntil
		{
			alpha.state.currentSnapshot.draft.isEmpty
		})
		alpha.service.emit(
			.itemStarted(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				item: try command(
					status: "inProgress",
					cwd: alpha.workspace.checkoutPath
				)
			)
		)
		var canceledQuit = 0
		var finished = 0
		fixture.coordinator.onStopAllFailed =
		{
			canceledQuit += 1
		}
		fixture.coordinator.onAllTasksFinished =
		{
			finished += 1
		}
		#expect(alpha.state.store.model.execution.activeThreadID == alpha.service.thread.id)
		#expect(alpha.state.store.model.execution.activeTurnID == alpha.service.turn.id)
		fixture.coordinator.stopAll()
		alpha.service.emit(
			.error(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				message: "Synthetic agent failure",
				willRetry: false
			)
		)
		let canceledByFatalOutcome: Bool
		if case .idle = fixture.coordinator.model.quit
		{
			canceledByFatalOutcome = true
		}
		else
		{
			canceledByFatalOutcome = false
		}
		try #require(
			canceledByFatalOutcome,
			"Fatal unresolved command must reject quit before waiting for its callback."
		)
		await waitForQuitCallback(fixture.coordinator)
		{
			canceledQuit == 1
		}
		#expect(canceledQuit == 1)
		#expect(finished == 0)
		#expect(alpha.state.currentSnapshot.taskOutcomeUncertain)
		#expect(!alpha.state.beginWorkspaceCleanup())
		alpha.service.emit(
			.itemCompleted(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				item: try command(
					status: "completed",
					cwd: alpha.workspace.checkoutPath
				)
			)
		)
		#expect(!fixture.coordinator.isTaskActive)
		#expect(!alpha.state.currentSnapshot.taskOutcomeUncertain)
		#expect(alpha.state.currentSnapshot.executionState == .failed)
		await waitForQuitCallback(fixture.coordinator)
		{
			finished == 1
		}
		#expect(finished == 1)
	}

	@Test func directRegistryOwnersKeepRepeatedApprovalsStopAndReconnectSeparate() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.store.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		let alphaStore = alpha.state.store
		let betaStore = beta.state.store

		let alphaReference = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: alpha.workspace.id,
				sessionID: alphaStore.model.identity.sessionID
			),
			workspace: alphaStore.model.identity
		)
		let betaReference = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: beta.workspace.id,
				sessionID: betaStore.model.identity.sessionID
			),
			workspace: betaStore.model.identity
		)

		alphaStore.inputs.updateDraft("Run alpha")
		betaStore.inputs.updateDraft("Run beta")
		let alphaSend = try #require(alphaStore.inputs.send())
		let betaSend = try #require(betaStore.inputs.send())
		#expect(await alphaSend.wait() == .finished)
		#expect(await betaSend.wait() == .finished)

		let alphaApproval = alpha.service.approval(id: "same-request")
		let betaApproval = beta.service.approval(id: "same-request")
		alpha.service.emit(.interaction(alphaApproval))
		beta.service.emit(.interaction(betaApproval))
		let betaGeneration = betaStore.model.connection.generation
		#expect(alphaStore.inputs.respond(
			to: betaApproval,
			with: .approval(.accept)
		) == nil)
		#expect(alpha.service.respondedRequestIDs.isEmpty)
		#expect(alphaStore.model.connection.isConnected)
		#expect(alphaStore.model.execution.activeThreadID == alphaApproval.threadId)
		#expect(alphaStore.model.execution.activeTurnID == alphaApproval.turnId)
		#expect(alphaStore.model.execution.pendingInteractions.contains
		{
			$0.id == alphaApproval.id && $0.threadId == alphaApproval.threadId
				&& $0.turnId == alphaApproval.turnId
		})
		let response = try #require(alphaStore.inputs.respond(
			to: alphaApproval,
			with: .approval(.accept)
		))
		#expect(await response.wait() == .finished)
		let stop = try #require(alphaStore.inputs.stop())
		#expect(await stop.wait() == .finished)
		#expect(alpha.service.interruptionRequests.count == 1)
		#expect(beta.service.interruptionRequests.isEmpty)
		alpha.service.complete(status: "interrupted")
		alpha.service.onDisconnect?("Reconnect only alpha")
		await alphaStore.inputs.connect()
		#expect(alphaStore.model.connection.generation > betaGeneration)
		#expect(betaStore.model.connection.generation == betaGeneration)
		#expect(betaStore.model.execution.pendingInteractions.map(\.id) == [betaApproval.id])
		#expect(betaStore.model.execution.state == .awaitingApproval)
		#expect(beta.service.respondedRequestIDs.isEmpty)
		#expect(beta.service.disconnectCount == 0)
		#expect(fixture.coordinator.store(for: alphaReference) === alphaStore)
		#expect(fixture.coordinator.store(for: betaReference) === betaStore)
		#expect(fixture.coordinator.store(owningThread: alpha.service.thread.id) === alphaStore)
	}

	@Test func duplicateBackendThreadIDsRequireTheCapturedRegistryOwner() async throws
	{
		let fixture = try TaskExecutionFixture(sharedThreadID: "same-thread")
		defer
		{
			fixture.remove()
		}
		let source = fixture.sourceState.store
		await source.inputs.connect()
		let alpha = try await fixture.createTask("Shared ID managed owner")
		for store in [source, alpha.state.store]
		{
			store.inputs.updateDraft("Bind independently")
			let handle = try #require(store.inputs.send())
			#expect(await handle.wait() == .finished)
		}
		try #require(source.model.execution.activeThreadID == "same-thread")
		try #require(alpha.state.store.model.execution.activeThreadID == "same-thread")
		try #require(alpha.state.store.model.lifecycle.managedWorkspace?.threadID == "same-thread")
		fixture.coordinator.selectSourceCheckout()
		let captured = fixture.coordinator.captureSelectedOwner()
		await fixture.coordinator.selectWorkspace(alpha.workspace.id)
		#expect(fixture.coordinator.store(owningThread: "same-thread") == nil)
		fixture.coordinator.selectThread("same-thread")
		#expect(fixture.coordinator.selectedStore === alpha.state.store)
		fixture.coordinator.selectThread(
			"same-thread",
			owner: captured.reference
		)
		await waitForCoordinator(fixture.coordinator)
		{
			fixture.coordinator.selectedStore === source
		}
		#expect(fixture.coordinator.selectedStore === source)
		#expect(fixture.coordinator.store(for: captured.reference) === source)
	}

	@Test func retiredOwnerCallbacksCannotRecreateStoreOrPublishTaskEvents() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.store.inputs.connect()
		let alpha = try await fixture.createTask("Retired")
		let beta = try await fixture.createTask("Survivor")
		let store = alpha.state.store
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .managed(
				workspaceID: alpha.workspace.id,
				sessionID: store.model.identity.sessionID
			),
			workspace: store.model.identity
		)
		let oldEvent = try #require(alpha.service.onEvent)
		let oldDisconnect = try #require(alpha.service.onDisconnect)
		await fixture.coordinator.removeCheckout(id: alpha.workspace.id)
		let beforeGeneration = store.model.connection.generation
		let survivorGeneration = beta.state.store.model.connection.generation
		var published = 0
		fixture.coordinator.onTaskSnapshot =
		{
			_ in published += 1
		}
		oldEvent(.interaction(alpha.service.approval(id: "Retired approval")))
		oldEvent(.turnStarted(
			threadId: alpha.service.thread.id,
			turn: alpha.service.turn
		))
		oldDisconnect("Retired disconnect")
		#expect(fixture.coordinator.store(for: reference) == nil)
		#expect(fixture.coordinator.store(owningThread: alpha.service.thread.id) == nil)
		#expect(store.model.connection.generation == beforeGeneration)
		#expect(store.model.execution.pendingInteractions.isEmpty)
		#expect(published == 0)
		#expect(beta.state.store.model.connection.generation == survivorGeneration)
		#expect(fixture.coordinator.currentSnapshot.taskWorkspaces.first(where:
			{
				$0.id == alpha.workspace.id
			})?.phase == .checkoutRemoved)
	}

	@Test func interleavedApprovalsProgressAndChangesStayWithTheirCheckout() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Change alpha")
		alpha.state.inputs.addDraftContext(
			ComposerContextItem(
				kind: .fileReference,
				title: "Alpha file",
				path: "tracked.txt"
			)
		)
		beta.state.inputs.updateDraft("Change beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		#expect(alpha.service.turnRequests[0].cwd?.path == alpha.workspace.checkoutPath)
		#expect(beta.service.turnRequests[0].cwd?.path == beta.workspace.checkoutPath)
		#expect(
			alpha.service.turnRequests[0].inputs.contains(
				.mention(
					name: "tracked.txt",
					path: alpha.workspace.checkoutPath + "/tracked.txt"
				)
			)
		)
		#expect(alpha.state.managedTaskWorkspace?.threadID == alpha.service.thread.id)
		#expect(beta.state.managedTaskWorkspace?.threadID == beta.service.thread.id)

		let alphaApproval = alpha.service.approval(id: "same-request-id")
		let betaApproval = beta.service.approval(id: "same-request-id")
		alpha.service.emit(.interaction(alphaApproval))
		beta.service.emit(.interaction(betaApproval))
		alpha.service.emit(
			.diffUpdated(
				threadId: alpha.service.thread.id,
				turnId: alpha.service.turn.id,
				diff:
				"diff --git a/alpha.txt b/alpha.txt\n--- a/alpha.txt\n+++ "
					+ "b/alpha.txt\n@@ -1 +1 @@\n-old\n+alpha\n"
			)
		)
		beta.service.emit(
			.planUpdated(
				try #require(
					TurnPlanUpdate(json: [
						"threadId": beta.service.thread.id,
						"turnId": beta.service.turn.id,
						"plan": [["step": "Check beta", "status": "inProgress"]],
					])
				)
			)
		)
		await fixture.coordinator.selectWorkspace(alpha.workspace.id)
		#expect(fixture.coordinator.currentSnapshot.pendingInteractions
			.map(\.id) == [alphaApproval.id])
		#expect(fixture.coordinator.currentSnapshot.diff.contains("+alpha"))
		#expect(fixture.coordinator.currentSnapshot.activePlan == nil)
		#expect(alpha.state.inputs.respond(
			to: betaApproval,
			with: .approval(.accept)
		) == nil)
		#expect(alpha.service.respondedRequestIDs.isEmpty)
		let response = try #require(alpha.state.inputs.respond(
			to: alphaApproval,
			with: .approval(.accept)
		))
		#expect(await response.wait() == .finished)
		#expect(alpha.service.respondedRequestIDs == [alphaApproval.id])
		#expect(beta.service.respondedRequestIDs.isEmpty)
		#expect(beta.state.currentSnapshot.pendingInteractions.count == 1)
		await fixture.coordinator.selectWorkspace(beta.workspace.id)
		#expect(fixture.coordinator.currentSnapshot.activePlan?.plan.first?.step == "Check beta")
		#expect(fixture.coordinator.currentSnapshot.diff.isEmpty)
		#expect(
			fixture.coordinator.currentSnapshot.taskStatusSummary
				== "2 running tasks · 1 need a response"
		)
		#expect(fixture.coordinator.store(owningThread: alpha.service.thread.id) === alpha.state
			.store)
	}

	@Test func steeringAndStopRemainIndependentAndQuitWaitsForEveryOwner() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Start alpha")
		beta.state.inputs.updateDraft("Start beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		alpha.service.suspendSteer = true
		alpha.state.inputs.updateDraft("Guide alpha")
		alpha.state.inputs.steer("Guide alpha")
		try #require(await waitUntil
		{
			alpha.service.pendingSteer != nil
		})
		await fixture.coordinator.selectWorkspace(beta.workspace.id)
		beta.state.inputs.updateDraft("Keep beta draft")
		alpha.service.pendingSteer?.resume(returning: alpha.service.turn.id)
		alpha.service.pendingSteer = nil
		try #require(await waitUntil
		{
			alpha.state.currentSnapshot.draft.isEmpty
		})
		#expect(beta.state.currentSnapshot.draft == "Keep beta draft")
		#expect(
			alpha.service.steeringRequests == [
				WorkspaceCodexService.TurnIdentity(
					threadID: alpha.service.thread.id,
					turnID: alpha.service.turn.id
				)
			]
		)
		#expect(beta.service.steeringRequests.isEmpty)
		alpha.state.inputs.stop()
		try #require(await waitUntil
		{
			alpha.service.interruptionRequests.count == 1
		})
		#expect(beta.service.interruptionRequests.isEmpty)
		#expect(beta.state.currentSnapshot.executionState == .running)

		var allFinishedCount = 0
		fixture.coordinator.onAllTasksFinished =
		{
			allFinishedCount += 1
		}
		fixture.coordinator.stopAll()
		try #require(await waitUntil
		{
			beta.service.interruptionRequests.count == 1
		})
		alpha.service.complete(status: "interrupted")
		#expect(fixture.coordinator.isTaskActive)
		#expect(allFinishedCount == 0)
		beta.service.complete(status: "interrupted")
		#expect(!fixture.coordinator.isTaskActive)
		await waitForQuitCallback(fixture.coordinator)
		{
			allFinishedCount == 1
		}
		#expect(allFinishedCount == 1)
		#expect(
			alpha.service.interruptionRequests == [
				WorkspaceCodexService.TurnIdentity(
					threadID: alpha.service.thread.id,
					turnID: alpha.service.turn.id
				)
			]
		)
		#expect(
			beta.service.interruptionRequests == [
				WorkspaceCodexService.TurnIdentity(
					threadID: beta.service.thread.id,
					turnID: beta.service.turn.id
				)
			]
		)
	}

	@Test func reconnectingOneOwnerPreservesItsDraftWithoutResendingOrChangingAnotherTask()
		async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.service.suspendTurnStart = true
		alpha.state.inputs.updateDraft("Uncertain alpha")
		beta.state.inputs.updateDraft("Run beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.pendingTurnStart != nil && beta.service.turnRequests.count == 1
			}
		)
		beta.service.emit(.interaction(beta.service.approval(id: "beta-approval")))
		alpha.service.onDisconnect?("Synthetic disconnect")
		alpha.service.pendingTurnStart?.resume(throwing: AppServerError.disconnected)
		alpha.service.pendingTurnStart = nil
		#expect(alpha.state.currentSnapshot.draft == "Uncertain alpha")
		#expect(!alpha.state.currentSnapshot.canSend)
		alpha.service.savedTurns = [alpha.service.finishedTurn(status: "completed")]
		await alpha.state.inputs.connect()
		#expect(alpha.state.currentSnapshot.canSend)
		#expect(alpha.state.currentSnapshot.draft == "Uncertain alpha")
		#expect(alpha.service.turnRequests.count == 1)
		#expect(beta.state.currentSnapshot.executionState == .awaitingApproval)
		#expect(beta.state.currentSnapshot.pendingInteractions.first?.id == "beta-approval")
		#expect(beta.service.disconnectCount == 0)
		#expect(beta.service.turnRequests.count == 1)
	}

	@Test func aConversationInAnotherCheckoutCannotReceiveTheTaskOrBindItsRecord() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let task = try await fixture.createTask("Wrong cwd")
		task.service.reportedDirectory = fixture.source
		task.state.inputs.updateDraft("Keep this input")
		task.state.inputs.send()
		try #require(await waitUntil
		{
			task.state.currentSnapshot.taskOutcomeUncertain
		})
		#expect(task.service.turnRequests.isEmpty)
		#expect(task.state.currentSnapshot.draft == "Keep this input")
		#expect(task.state.managedTaskWorkspace?.threadID == nil)
		#expect(try await fixture.manager.activeCheckout(id: task.workspace.id).threadID == nil)
	}

	@Test func relaunchRestoresEachBoundConversationAndUnsentContextWithoutStartingATurn()
		async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Run alpha")
		beta.state.inputs.updateDraft("Run beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		alpha.service.complete(status: "completed")
		beta.service.complete(status: "completed")
		alpha.state.inputs.updateDraft("Saved alpha")
		alpha.state.inputs.addDraftContext(
			ComposerContextItem(
				kind: .fileReference,
				title: "Alpha",
				path: "tracked.txt"
			)
		)
		beta.state.inputs.updateDraft("Saved beta")
		try await alpha.state.store.awaitAcceptedPersistence()
		try await beta.state.store.awaitAcceptedPersistence()
		fixture.coordinator.shutdown()

		let restored = fixture.restoredCoordinator()
		defer
		{
			restored.shutdown()
		}
		await restored.sourceStore.inputs.connect()
		await restored.reloadWorkspaces()
		await restored.selectWorkspace(alpha.workspace.id)
		try #require(await waitUntil
		{
			restored.currentSnapshot.canSend
		})
		#expect(restored.currentSnapshot.selectedThreadID == alpha.service.thread.id)
		#expect(restored.currentSnapshot.draft == "Saved alpha")
		#expect(restored.currentSnapshot.draftContext.map(\.title) == ["Alpha"])
		await restored.selectWorkspace(beta.workspace.id)
		try #require(await waitUntil
		{
			restored.currentSnapshot.canSend
		})
		#expect(restored.currentSnapshot.selectedThreadID == beta.service.thread.id)
		#expect(restored.currentSnapshot.draft == "Saved beta")
		#expect(restored.currentSnapshot.draftContext.isEmpty)
		#expect(!restored.isTaskActive)
		let restoredAlpha = try #require(fixture.restoredServices[alpha.workspace.id])
		let restoredBeta = try #require(fixture.restoredServices[beta.workspace.id])
		#expect(restoredAlpha.turnRequests.isEmpty)
		#expect(restoredBeta.turnRequests.isEmpty)
	}

	@Test func notificationTransitionsRemainIndependentDuringInterleavedSnapshots() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		var tracker = TaskNotificationCollection()
		var events: [TaskNotificationEvent] = []
		fixture.coordinator.onTaskSnapshot =
		{
			snapshot in
			if let event = tracker.observe(snapshot)
			{
				events.append(event)
			}
		}
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Run alpha")
		beta.state.inputs.updateDraft("Run beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		alpha.service.emit(.interaction(alpha.service.approval(id: "same-id")))
		beta.service.emit(.interaction(beta.service.approval(id: "same-id")))
		alpha.state.inputs.updateDraft("Publish alpha snapshot")
		beta.state.inputs.updateDraft("Publish beta snapshot")
		alpha.service.complete(status: "completed")
		beta.state.inputs.updateDraft("Beta is still waiting")
		#expect(
			events.filter
			{
				$0.title == "Approval needed"
			}.map(\.threadID) == [
				alpha.service.thread.id,
				beta.service.thread.id,
			]
		)
		#expect(
			events.filter
			{
				$0.title == "Task completed"
			}.map(\.threadID) == [alpha.service.thread.id]
		)
		#expect(beta.state.currentSnapshot.pendingInteractions.count == 1)
	}

	@Test func cleanupDrainsOnlyItsOwnerThenRevalidatesFreshFilesAndDurableBinding() async throws
	{
		for change in ["dirty", "binding", "clean"]
		{
			let gate = LifecyclePersistenceGate()
			let fixture = try TaskExecutionFixture(persistenceGate: gate)
			defer
			{
				fixture.remove()
			}
			await fixture.sourceState.store.inputs.connect()
			let alpha = try await fixture.createTask("Cleanup alpha")
			let beta = try await fixture.createTask("Keep beta")
			let alphaStore = alpha.state.store
			let betaStore = beta.state.store
			gate.blockedPaths = [alpha.workspace.checkoutPath, beta.workspace.checkoutPath]
			alphaStore.inputs.updateDraft("Accepted alpha write")
			betaStore.inputs.updateDraft("Accepted beta write")
			let alphaWrite = try #require(draftHandle(alphaStore))
			let betaWrite = try #require(draftHandle(betaStore))
			await gate.waitForWrite(at: alpha.workspace.checkoutPath)
			await gate.waitForWrite(at: beta.workspace.checkoutPath)
			let removal = Task
			{
				await fixture.coordinator.removeCheckout(id: alpha.workspace.id)
			}
			await waitForCoordinator(fixture.coordinator)
			{
				fixture.coordinator.model.pendingCleanup[alpha.workspace.id]?.stage == .draining
			}
			#expect(alphaStore.model.lifecycle.cleanupReservation != nil)
			#expect(!alphaStore.currentSnapshot.canSend)
			#expect(alphaStore.inputs.send() == nil)
			#expect(FileManager.default.fileExists(atPath: alpha.workspace.checkoutPath))
			#expect(betaStore.model.lifecycle.cleanupReservation == nil)
			#expect(betaStore.currentSnapshot.draft == "Accepted beta write")
			if change == "dirty"
			{
				try "Changed during persistence drain".write(
					to: URL(fileURLWithPath: alpha.workspace.checkoutPath)
						.appendingPathComponent("tracked.txt"),
					atomically: true,
					encoding: .utf8
				)
			}
			else if change == "binding"
			{
				_ = try await fixture.manager.bindThread(
					id: alpha.workspace.id,
					threadID: "New durable binding"
				)
			}
			gate.release(alpha.workspace.checkoutPath)
			#expect(await alphaWrite.wait() == .finished)
			await removal.value
			#expect(betaWrite.completion == nil)
			#expect(betaStore.model.lifecycle.cleanupReservation == nil)
			#expect(fixture.storage.draft(
				for: URL(fileURLWithPath: alpha.workspace.checkoutPath),
				threadID: nil
			) == "Accepted alpha write")
			#expect(FileManager.default
				.fileExists(atPath: alpha.workspace.checkoutPath) == (change != "clean"))
			if change != "clean"
			{
				#expect(alphaStore.model.lifecycle.cleanupReservation == nil)
				alphaStore.inputs.updateDraft("Editable after rejected cleanup")
				#expect(alphaStore.currentSnapshot.draft == "Editable after rejected cleanup")
				_ = await draftHandle(alphaStore)?.wait()
			}
			gate.release(beta.workspace.checkoutPath)
			#expect(await betaWrite.wait() == .finished)
			#expect(fixture.storage.draft(
				for: URL(fileURLWithPath: beta.workspace.checkoutPath),
				threadID: nil
			) == "Accepted beta write")
		}
	}

	@Test func cleanupRefusesAnActiveOrDirtyOwnerAndRetainsTheRemovedBranch() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let task = try await fixture.createTask("Cleanup")
		task.state.inputs.updateDraft("Run cleanup task")
		task.state.inputs.send()
		try #require(await waitUntil
		{
			task.service.turnRequests.count == 1
		})
		await fixture.coordinator.removeCheckout(id: task.workspace.id)
		#expect(FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		task.service.complete(status: "completed")
		let dirtyFile = URL(fileURLWithPath: task.workspace.checkoutPath).appendingPathComponent(
			"keep.txt"
		)
		try "keep".write(
			to: dirtyFile,
			atomically: true,
			encoding: .utf8
		)
		await fixture.coordinator.removeCheckout(id: task.workspace.id)
		#expect(try String(
			contentsOf: dirtyFile,
			encoding: .utf8
		) == "keep")
		try FileManager.default.removeItem(at: dirtyFile)
		await fixture.coordinator.removeCheckout(id: task.workspace.id)
		#expect(!FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		#expect(fixture.coordinator.currentSnapshot.selectedTaskWorkspaceID == nil)
		#expect(fixture.coordinator.currentSnapshot.taskWorkspaces.first?.phase == .checkoutRemoved)
		#expect(fixture.coordinator.currentSnapshot.taskWorkspaces.first?
			.canRemoveCheckout == false)
		#expect(
			try fixture.git(
				["rev-parse", task.workspace.branch],
				at: fixture.source
			)
				== task.workspace.baseCommit
		)
	}

	@Test func restoredBoundTaskMustBeReconciledBeforeCleanupAndRunningHistoryBlocksRemoval()
		async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let task = try await fixture.createTask("Still running")
		task.state.inputs.updateDraft("Run task")
		task.state.inputs.send()
		try #require(await waitUntil
		{
			task.service.turnRequests.count == 1
		})
		task.service.savedTurns = [task.service.turn]
		fixture.coordinator.shutdown()
		let restored = fixture.restoredCoordinator()
		defer
		{
			restored.shutdown()
		}
		await restored.sourceStore.inputs.connect()
		await restored.reloadWorkspaces()
		#expect(restored.currentSnapshot.taskWorkspaces.first?.canRemoveCheckout == false)
		await restored.removeCheckout(id: task.workspace.id)
		#expect(FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		await restored.selectWorkspace(task.workspace.id)
		try #require(await waitUntil
		{
			restored.currentSnapshot.taskOutcomeUncertain
		})
		await restored.removeCheckout(id: task.workspace.id)
		#expect(FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		#expect(!restored.currentSnapshot.canSend)
	}

	@Test func failedStopCancelsTheQuitWaitWhilePreservingUnknownOutcomeAndOtherOwners(
	) async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Run alpha")
		beta.state.inputs.updateDraft("Run beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		alpha.state.inputs.updateDraft("Recover alpha draft")
		alpha.service.interruptError = AppServerError.protocolError("Synthetic stop timeout")
		var canceledQuitCount = 0
		var completedQuitCount = 0
		fixture.coordinator.onStopAllFailed =
		{
			canceledQuitCount += 1
		}
		fixture.coordinator.onAllTasksFinished =
		{
			completedQuitCount += 1
		}
		fixture.coordinator.stopAll()
		try #require(await waitUntil
		{
			canceledQuitCount == 1
		})
		#expect(completedQuitCount == 0)
		#expect(alpha.state.currentSnapshot.taskOutcomeUncertain)
		#expect(alpha.state.currentSnapshot.draft == "Recover alpha draft")
		#expect(!alpha.state.currentSnapshot.canSend)
		#expect(beta.state.currentSnapshot.executionState == .stopping)
		#expect(fixture.coordinator.isTaskActive)
	}

	@Test func quitWaitsForActualCommandExitAndEveryOwnersAcceptedDraftWrites() async throws
	{
		let gate = LifecyclePersistenceGate()
		let fixture = try TaskExecutionFixture(persistenceGate: gate)
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.store.inputs.connect()
		let alpha = try await fixture.createTask("Quit alpha")
		let beta = try await fixture.createTask("Quit beta")
		let alphaStore = alpha.state.store
		let betaStore = beta.state.store

		alphaStore.inputs.updateDraft("Run alpha")
		betaStore.inputs.updateDraft("Run beta")
		let alphaSend = try #require(alphaStore.inputs.send())
		let betaSend = try #require(betaStore.inputs.send())
		_ = await alphaSend.wait()
		_ = await betaSend.wait()

		let running = try command(
			status: "inProgress",
			cwd: alpha.workspace.checkoutPath
		)
		alpha.service.emit(.itemStarted(
			threadId: alpha.service.thread.id,
			turnId: alpha.service.turn.id,
			item: running
		))
		gate.blockedPaths = [alpha.workspace.checkoutPath, beta.workspace.checkoutPath]
		alphaStore.inputs.updateDraft("Persist alpha before quit")
		betaStore.inputs.updateDraft("Persist beta before quit")
		let alphaWrite = try #require(draftHandle(alphaStore))
		let betaWrite = try #require(draftHandle(betaStore))
		await gate.waitForWrite(at: alpha.workspace.checkoutPath)
		await gate.waitForWrite(at: beta.workspace.checkoutPath)
		var completed = 0
		var canceled = 0
		fixture.coordinator.onAllTasksFinished =
		{
			completed += 1
		}
		fixture.coordinator.onStopAllFailed =
		{
			canceled += 1
		}
		fixture.coordinator.onConfirmQuit =
		{
			fixture.coordinator.confirmQuit(
				$0,
				approved: true
			)
		}
		let quitRequest = fixture.coordinator.requestQuit()
		await alpha.service.waitForCheckpoint("interrupt:1")
		await beta.service.waitForCheckpoint("interrupt:1")
		#expect(alphaStore.model.lifecycle.quitReservation != nil)
		#expect(betaStore.model.lifecycle.quitReservation != nil)
		#expect(fixture.sourceState.store.model.lifecycle.quitReservation != nil)
		#expect(alphaStore.inputs.send() == nil)
		#expect(betaStore.inputs.send() == nil)
		let interrupted = CodexTurn(
			id: alpha.service.turn.id,
			status: "interrupted",
			items: [running],
			error: nil
		)
		alpha.service.savedTurns = [interrupted]
		alpha.service.emit(.turnCompleted(
			threadId: alpha.service.thread.id,
			turn: interrupted
		))
		beta.service.complete(status: "interrupted")
		#expect(completed == 0)
		#expect(fixture.coordinator.isTaskActive)
		#expect(alphaStore.model.execution.commandLifetime.hasPendingCommands)
		alpha.service.emit(.itemCompleted(
			threadId: alpha.service.thread.id,
			turnId: alpha.service.turn.id,
			item: try command(
				status: "completed",
				cwd: alpha.workspace.checkoutPath
			)
		))
		await waitForCoordinator(fixture.coordinator)
		{
			if case .draining = fixture.coordinator.model.quit
			{
				return true
			}
			return false
		}
		#expect(completed == 0)
		gate.release(alpha.workspace.checkoutPath)
		#expect(await alphaWrite.wait() == .finished)
		#expect(completed == 0)
		#expect(betaWrite.completion == nil)
		gate.release(beta.workspace.checkoutPath)
		#expect(await betaWrite.wait() == .finished)
		await waitForCoordinator(fixture.coordinator)
		{
			if case .terminating(
				let request,
				_
			) = fixture.coordinator.model.quit,
				request == quitRequest
			{
				return true
			}
			return false
		}
		await waitForQuitCallback(fixture.coordinator)
		{
			completed == 1
		}
		#expect(completed == 1)
		#expect(canceled == 0)
		#expect(alphaStore.model.lifecycle.quitReservation?.requestID == quitRequest.requestID)
		#expect(betaStore.model.lifecycle.quitReservation?.requestID == quitRequest.requestID)
		#expect(fixture.sourceState.store.model.lifecycle.quitReservation?.requestID
			== quitRequest.requestID)

		#expect(fixture.storage.draft(
			for: URL(fileURLWithPath: alpha.workspace.checkoutPath),
			threadID: alpha.service.thread.id
		) ==
			"Persist alpha before quit")
		#expect(fixture.storage.draft(
			for: URL(fileURLWithPath: beta.workspace.checkoutPath),
			threadID: beta.service.thread.id
		) ==
			"Persist beta before quit")
	}

	@Test func completedPersistenceFailureCancelsQuitUntilSuccessfulSupersedingWrite() async throws
	{
		let gate = LifecyclePersistenceGate()
		let fixture = try TaskExecutionFixture(persistenceGate: gate)
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.store.inputs.connect()
		let owner = try await fixture.createTask("Failed persistence")
		let store = owner.state.store
		gate.blockedPaths = [owner.workspace.checkoutPath]
		store.inputs.updateDraft("Visible failed write")
		let failed = try #require(draftHandle(store))
		await gate.waitForWrite(at: owner.workspace.checkoutPath)
		gate.release(
			owner.workspace.checkoutPath,
			failure: AppServerError.protocolError("Controlled write failure")
		)
		if case .failed = await failed.wait()
		{
		}
		else
		{
			Issue.record("Expected write failure")
		}
		var canceled = 0
		var completed = 0
		fixture.coordinator.onStopAllFailed =
		{
			canceled += 1
		}
		fixture.coordinator.onAllTasksFinished =
		{
			completed += 1
		}
		fixture.coordinator.onConfirmQuit =
		{
			fixture.coordinator.confirmQuit(
				$0,
				approved: true
			)
		}
		fixture.coordinator.requestQuit()
		await waitForQuitCallback(fixture.coordinator)
		{
			canceled == 1
		}
		#expect(completed == 0)
		#expect(store.model.lifecycle.quitReservation == nil)
		#expect(store.currentSnapshot.draft == "Visible failed write")
		store.inputs.updateDraft("Successful replacement")
		let replacement = try #require(draftHandle(store))
		#expect(await replacement.wait() == .finished)
		let retryQuit = fixture.coordinator.requestQuit()
		await waitForQuitCallback(fixture.coordinator)
		{
			completed == 1
		}
		if case .terminating(
			let request,
			_
		) = fixture.coordinator.model.quit
		{
			#expect(request == retryQuit)
		}
		else
		{
			Issue.record("Successful quit must remain in terminating state.")
		}
		#expect(store.model.lifecycle.quitReservation?.requestID == retryQuit.requestID)
		#expect(canceled == 1)
		#expect(fixture.storage.draft(
			for: URL(fileURLWithPath: owner.workspace.checkoutPath),
			threadID: nil
		) == "Successful replacement")
	}

	@Test func unknownPreparationAfterNewChatStillRefusesNormalQuit() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		let store = fixture.sourceState.store
		await store.inputs.connect()
		fixture.sourceService.suspendThreadStart = true
		store.inputs.updateDraft("Captured original request")
		let submission = try #require(store.inputs.send())
		await fixture.sourceService.waitForCheckpoint("threadStart")
		store.inputs.newChat()
		store.inputs.updateDraft("Independent later draft")
		fixture.sourceService.pendingThreadStart?.resume(
			throwing: AppServerError.requestTimedOut("thread/start")
		)
		fixture.sourceService.pendingThreadStart = nil
		_ = await submission.wait()
		#expect(store.model.execution.activeThreadID == nil)
		#expect(!store.model.composer.pendingSubmissions.isEmpty)
		#expect(!store.model.composer.uncertainSubmissions.isEmpty)
		#expect(store.currentSnapshot.draft == "Independent later draft")
		var canceled = 0
		var completed = 0
		fixture.coordinator.onStopAllFailed =
		{
			canceled += 1
		}
		fixture.coordinator.onAllTasksFinished =
		{
			completed += 1
		}
		fixture.coordinator.onConfirmQuit =
		{
			fixture.coordinator.confirmQuit(
				$0,
				approved: true
			)
		}
		fixture.coordinator.requestQuit()
		await waitForQuitCallback(fixture.coordinator)
		{
			canceled == 1
		}
		#expect(completed == 0)
		#expect(store.model.lifecycle.quitReservation == nil)
		#expect(store.currentSnapshot.draft == "Independent later draft")
		#expect(!store.model.composer.pendingSubmissions.isEmpty)
	}

	@Test func reentrantQuitReservationFailureNeverStopsOrQueuesALaterFreeze() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		let store = fixture.sourceState.store
		await store.inputs.connect()
		var results: [Bool] = []
		fixture.coordinator.onConfirmQuit =
		{
			fixture.coordinator.confirmQuit(
				$0,
				approved: true
			)
		}
		fixture.coordinator.onQuitCompleted =
		{
			_, approved in results.append(approved)
		}
		var armed = false
		let observer = store.observe
		{
			_ in
			guard armed
			else
			{
				return
			}
			armed = false
			fixture.coordinator.requestQuit()
		}
		defer
		{
			store.removeObserver(observer)
		}
		armed = true
		store.inputs.updateDraft("Trigger observed mutation")
		_ = await draftHandle(store)?.wait()
		await waitForQuitCallback(fixture.coordinator)
		{
			results == [false]
		}
		#expect(results == [false])
		#expect(store.model.lifecycle.quitReservation == nil)
		#expect(fixture.sourceService.interruptionRequests.isEmpty)
		#expect(store.currentSnapshot.draft == "Trigger observed mutation")
	}

	@Test func completingDuringQuitConfirmationDoesNotLeaveADeferredQuitWaiting() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let task = try await fixture.createTask("Fast completion")
		task.state.inputs.updateDraft("Run task")
		task.state.inputs.send()
		try #require(await waitUntil
		{
			task.service.turnRequests.count == 1
		})
		let (quitRequest, approved) = await observedQuitOutcome(fixture.coordinator)
		{
			_ in
			task.service.complete(status: "completed")
			return true
		}
		#expect(approved)
		if case .terminating(
			let current,
			_
		) = fixture.coordinator.model.quit
		{
			#expect(current == quitRequest)
		}
		else
		{
			Issue.record("Accepted ordinary quit must remain frozen until shutdown.")
		}
		#expect(!fixture.coordinator.isTaskActive)
		#expect(task.service.interruptionRequests.isEmpty)
	}

	@Test func interruptedRemovalOfALockedCheckoutCanBeReopenedAndRetriedSafely() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let task = try await fixture.createTask("Locked cleanup")
		_ = try fixture.git(
			["worktree", "lock", task.workspace.checkoutPath],
			at: fixture.source
		)
		var cleanupStages: [WorkspaceCleanupTransition.Stage] = []
		fixture.coordinator.onChange =
		{
			_ in
			if let stage = fixture.coordinator.model.pendingCleanup[task.workspace.id]?.stage
			{
				cleanupStages.append(stage)
			}
		}
		await fixture.coordinator.removeCheckout(id: task.workspace.id)
		#expect(FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		let cleanupDiagnostic = "Locked removal must reach Git stage; observed \(cleanupStages), "
			+ "message: \(fixture.coordinator.model.message ?? "none"), "
			+ "owner: \(task.state.store.lifecycleObservation)."
		try #require(
			cleanupStages.contains(.removing),
			"\(cleanupDiagnostic)"
		)

		#expect(try TaskWorkspaceStore(directory: fixture.root.appendingPathComponent("records"))
			.load(id: task.workspace.id)?.phase == .removing)
		#expect(task.state.store.model.lifecycle.managedWorkspace?.phase == .removing)
		try #require(task.state.store.model.lifecycle.managedWorkspace?.phase == .removing)
		task.state.store.inputs.updateDraft("Keep local input while removal is incomplete")
		try await task.state.store.awaitAcceptedPersistence()
		#expect(task.state.currentSnapshot.draft == "Keep local input while removal is incomplete")
		#expect(!task.state.currentSnapshot.canSend)
		#expect(task.state.store.inputs.send() == nil)
		_ = try fixture.git(
			["worktree", "unlock", task.workspace.checkoutPath],
			at: fixture.source
		)
		await fixture.coordinator.removeCheckout(id: task.workspace.id)
		#expect(!FileManager.default.fileExists(atPath: task.workspace.checkoutPath))
		#expect(
			try fixture.git(
				["rev-parse", task.workspace.branch],
				at: fixture.source
			)
				== task.workspace.baseCommit
		)
	}

	@Test func changingACheckoutBranchBlocksSteeringWithoutAffectingAnotherOwner() async throws
	{
		let fixture = try TaskExecutionFixture()
		defer
		{
			fixture.remove()
		}
		await fixture.sourceState.inputs.connect()
		let alpha = try await fixture.createTask("Alpha")
		let beta = try await fixture.createTask("Beta")
		alpha.state.inputs.updateDraft("Run alpha")
		beta.state.inputs.updateDraft("Run beta")
		alpha.state.inputs.send()
		beta.state.inputs.send()
		try #require(
			await waitUntil
			{
				alpha.service.turnRequests.count == 1 && beta.service.turnRequests.count == 1
			}
		)
		_ = try fixture.git(
			["switch", "-c", "changed-owner"],
			at: URL(fileURLWithPath: alpha.workspace.checkoutPath)
		)
		alpha.state.inputs.updateDraft("Do not redirect me")
		alpha.state.inputs.steer("Do not redirect me")
		try #require(await waitUntil
		{
			alpha.state.currentSnapshot.taskOutcomeUncertain
		})
		#expect(alpha.service.steeringRequests.isEmpty)
		#expect(alpha.state.currentSnapshot.draft == "Do not redirect me")
		#expect(beta.state.currentSnapshot.executionState == .running)
		#expect(beta.service.turnRequests.count == 1)
	}

	private func draftHandle(_ store: WorkspaceStateStore) -> WorkspaceOperationHandle?
	{
		guard let requestID = store.model.composer.pendingDraftWrites[
			store.model.conversations.selectedConversation
		]
		else
		{
			return nil
		}
		return store.operation(for: OperationContext(
			workspace: store.model.identity,
			generation: store.model.connection.generation,
			requestID: requestID
		))
	}

	private func waitForQuitCallback(
		_ coordinator: TaskWorkspaceCoordinator,
		until condition: @escaping @MainActor () -> Bool
	) async
	{
		guard !condition()
		else
		{
			return
		}
		let previousFinished = coordinator.onAllTasksFinished
		let previousFailed = coordinator.onStopAllFailed
		await withCheckedContinuation
		{
			continuation in
			let check: @MainActor () -> Void =
			{
				guard condition()
				else
				{
					return
				}
				coordinator.onAllTasksFinished = previousFinished
				coordinator.onStopAllFailed = previousFailed
				continuation.resume()
			}
			coordinator.onAllTasksFinished =
			{
				previousFinished?()
				check()
			}
			coordinator.onStopAllFailed =
			{
				previousFailed?()
				check()
			}
		}
	}

	private func waitForCoordinator(
		_ coordinator: TaskWorkspaceCoordinator,
		until condition: @escaping @MainActor () -> Bool
	) async
	{
		guard !condition()
		else
		{
			return
		}
		let previous = coordinator.onChange
		await withCheckedContinuation
		{
			continuation in
			coordinator.onChange =
			{
				snapshot in
				previous?(snapshot)
				guard condition()
				else
				{
					return
				}
				coordinator.onChange = previous
				continuation.resume()
			}
		}
	}

	private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool
	{
		for _ in 0 ..< 300
		{
			if condition()
			{
				return true
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		return condition()
	}
}

@MainActor
private final class LifecyclePersistenceGate
{
	var blockedPaths: Set<String> = []
	private var writes: [String: CheckedContinuation<Void, Error>] = [:]
	private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

	func pause(_ write: WorkspaceDraftWrite) async throws
	{
		guard let path = write.context.workspace.canonicalCheckoutPath,
				blockedPaths.contains(path)
		else
		{
			return
		}
		try await withCheckedThrowingContinuation
		{
			writes[path] = $0
			for waiter in waiters.removeValue(forKey: path) ?? []
			{
				waiter.resume()
			}
		}
	}

	func waitForWrite(at path: String) async
	{
		guard writes[path] == nil
		else
		{
			return
		}
		await withCheckedContinuation
		{
			waiters[path, default: []].append($0)
		}
	}

	func release(
		_ path: String,
		failure: Error? = nil
	)
	{
		blockedPaths.remove(path)
		let continuation = writes.removeValue(forKey: path)
		if let failure
		{
			continuation?.resume(throwing: failure)
		}
		else
		{
			continuation?.resume()
		}
	}
}

@MainActor
private final class TaskExecutionFixture
{
	struct TaskOwner
	{
		let workspace: TaskWorkspace
		let state: WorkspaceTestFixture
		let service: WorkspaceCodexService
	}

	let root: URL
	let source: URL
	let manager: GitWorktreeManager
	let storage: LocalStorage
	let sourceService: WorkspaceCodexService
	let sourceState: WorkspaceTestFixture
	let coordinator: TaskWorkspaceCoordinator
	private(set) var restoredServices: [UUID: WorkspaceCodexService] = [:]

	init(
		persistenceGate: LifecyclePersistenceGate? = nil,
		sharedThreadID: String? = nil
	) throws
	{
		root = FileManager.default.temporaryDirectory.appendingPathComponent(
			"CodexGUI-TaskExecution-\(UUID().uuidString)",
			isDirectory: true
		).standardizedFileURL.resolvingSymlinksInPath()
		source = root.appendingPathComponent(
			"source",
			isDirectory: true
		)
		try Self.prepareSourceRepository(at: source)
		manager = GitWorktreeManager(
			recordDirectory: root.appendingPathComponent("records"),
			checkoutRoot: root.appendingPathComponent("checkouts")
		)
		let defaults = UserDefaults(suiteName: "TaskExecution.\(UUID().uuidString)")!
		storage = LocalStorage(defaults: defaults)
		if let persistenceGate
		{
			let sharedStorage = storage
			storage.workspacePersistenceScheduler = WorkspacePersistenceScheduler(writeDraft:
				{
					write in
					try await persistenceGate.pause(write)
					let path = try #require(write.context.workspace.canonicalCheckoutPath)
					let project = URL(fileURLWithPath: path)
					let threadID: String?
					switch write.conversation
					{
					case .newChat:
						threadID = nil
					case .thread(let id):
						threadID = id
					}
					sharedStorage.saveDraft(
						write.draft.text,
						for: project,
						threadID: threadID
					)
					sharedStorage.saveDraftContext(
						write.draft.context,
						for: project,
						threadID: threadID
					)
				})
		}
		storage.rememberProject(source)
		sourceService = WorkspaceCodexService(
			directory: source,
			threadID: sharedThreadID ?? "source"
		)
		sourceState = WorkspaceTestFixture(
			server: sourceService,
			storage: storage
		)
		let sharedStorage = storage
		var capturedServices: [UUID: WorkspaceCodexService] = [:]
		let sharedManager = manager
		coordinator = TaskWorkspaceCoordinator(
			sourceStore: sourceState.store,
			manager: manager
		)
		{
			configuration in
			let workspace = configuration.managedWorkspace!
			let service = WorkspaceCodexService(
				directory: URL(fileURLWithPath: workspace.checkoutPath),
				threadID: sharedThreadID ?? "thread-\(workspace.id)"
			)
			capturedServices[workspace.id] = service
			return WorkspaceStoreFactory.make(
				configuration: configuration,
				dependencies: WorkspaceStoreDependencies(
					service: service,
					storage: sharedStorage,
					manager: sharedManager
				)
			)
		}
		servicesProvider =
		{
			capturedServices
		}
	}

	private static func prepareSourceRepository(at source: URL) throws
	{
		try FileManager.default.createDirectory(
			at: source,
			withIntermediateDirectories: true
		)
		_ = try Self.runGit(
			["init", "-q"],
			at: source
		)
		try "committed\n".write(
			to: source.appendingPathComponent("tracked.txt"),
			atomically: true,
			encoding: .utf8
		)
		_ = try Self.runGit(
			["add", "tracked.txt"],
			at: source
		)
		_ = try Self.runGit(
			[
				"-c",
				"user.name=Task Test",
				"-c",
				"user.email=task@example.test",
				"commit",
				"-qm",
				"Initial",
			],
			at: source
		)
	}

	private var servicesProvider: (() -> [UUID: WorkspaceCodexService])!

	func createTask(_ name: String) async throws -> TaskOwner
	{
		let workspace = try #require(await coordinator.createTask(named: name))
		let state = WorkspaceTestFixture(store: coordinator.selectedStore)
		for _ in 0 ..< 300
		{
			if state.currentSnapshot.canSend
			{
				break
			}
			try? await Task.sleep(for: .milliseconds(5))
		}
		#expect(state.currentSnapshot.canSend)
		let service = try #require(servicesProvider()[workspace.id])
		return TaskOwner(
			workspace: workspace,
			state: state,
			service: service
		)
	}

	func restoredCoordinator(services: [UUID: WorkspaceCodexService] = [:])
		-> TaskWorkspaceCoordinator
	{
		let savedByThread = Dictionary(
			uniqueKeysWithValues: servicesProvider().values.map
			{
				($0.thread.id, $0.savedTurns)
			}
		)
		let sharedStorage = storage
		let sourceState = WorkspaceTestFixture(
			server: WorkspaceCodexService(
				directory: source,
				threadID: "source"
			),
			storage: storage
		)
		let sharedManager = manager
		return TaskWorkspaceCoordinator(
			sourceStore: sourceState.store,
			manager: manager
		)
		{
			[weak self] configuration in
			let workspace = configuration.managedWorkspace!
			let service = services[workspace.id] ?? WorkspaceCodexService(
				directory: URL(fileURLWithPath: workspace.checkoutPath),
				threadID: workspace.threadID ?? "thread-\(workspace.id)"
			)
			if services[workspace.id] == nil
			{
				service.savedTurns = savedByThread[service.thread.id] ?? []
			}
			self?.restoredServices[workspace.id] = service
			return WorkspaceStoreFactory.make(
				configuration: configuration,
				dependencies: WorkspaceStoreDependencies(
					service: service,
					storage: sharedStorage,
					manager: sharedManager
				)
			)
		}
	}

	func git(
		_ arguments: [String],
		at directory: URL
	) throws -> String
	{
		try Self.runGit(
			arguments,
			at: directory
		)
	}

	private static func runGit(
		_ arguments: [String],
		at directory: URL
	) throws -> String
	{
		let result = try GitTestCommandRunner.run(
			in: directory,
			arguments: arguments,
			captureStandardError: true
		)
		let text = String(
			decoding: result.output,
			as: UTF8.self
		).trimmingCharacters(in: .newlines)
		guard result.terminationStatus == 0
		else
		{
			throw TaskWorkspaceError.gitFailure(text)
		}
		return text
	}

	func remove()
	{
		coordinator.shutdown()
		try? FileManager.default.removeItem(at: root)
	}
}
