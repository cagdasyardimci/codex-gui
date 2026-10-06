import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct ComposerCommandRuntimeTests
{
	@Test
	func forkRetainsOriginalSelectionAndDraftUntilReturnedThreadIsAccepted() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/fork")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingFork != nil
		})
		#expect(fixture.store.model.conversations.selectedConversation == fixture.conversation)
		#expect(fixture.draft == original)
		#expect(fixture.store.model.composerCommands.pendingFork?.draft.context == [attachment])
		#expect(fixture.service.forkRequests.map(\.id) == [fixture.service.base.thread.id])
		#expect(fixture.service.forkRequests.first?.directory?.path == fixture.project.path)
		#expect(fixture.service.base.turnStartCount == 0)
		#expect(!fixture.state.currentSnapshot.canSend)
		let returned = fixture.detail(id: "forked-thread")
		fixture.service.finishFork(returned)
		#expect(await operation.wait() == .finished)
		try #require(await fixture.eventually
		{
			fixture.store.model.conversations.selectedConversation == .thread(returned.summary.id)
				&& fixture.store.model.conversations.pendingSelection == nil
		})
		#expect(fixture.store.model.identity.canonicalCheckoutPath == returned.summary.cwd)
		#expect(fixture.store.model.conversations.boundThreadID == nil)
		#expect(fixture.store.model.composerCommands.pendingFork == nil)
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.draft.context == [attachment])
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func inlinePlanSendsArgumentAndModeWhileCapturingOriginalDraftAndAttachment() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.service.base.suspendTurnStart = true
		fixture.state.inputs.updateDraft("/plan Inspect the fixture")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.base.pendingTurnStart != nil
		})
		let submitted = try #require(fixture.store.model.composer.pendingSubmissions.values.first)
		#expect(submitted.draft == original)
		#expect(submitted.draft.context == [attachment])
		#expect(fixture.draft == original)
		let mode = try #require(fixture.service.turnModes.first ?? nil)
		#expect(mode.mode == .plan)
		#expect(mode.model == "fixture-model")
		#expect(mode.reasoningEffort == "medium")
		let inputs = try #require(fixture.service.base.sentInputRequests.first)
		guard case .text(let sentText) = inputs.first
		else
		{
			Issue.record("Expected text followed by the attached file mention")
			return
		}
		#expect(sentText.hasPrefix("Inspect the fixture"))
		#expect(!sentText.contains("/plan"))
		#expect(inputs.contains(.mention(
			name: "evidence.txt",
			path: fixture.project.appendingPathComponent("evidence.txt").path
		)))
		fixture.state.inputs.updateDraft("A newer draft")
		fixture.service.base.finishTurnStart(with: fixture.service.base.nextTurn)
		#expect(await operation.wait() == .finished)
		#expect(fixture.draft.text == "A newer draft")
		#expect(fixture.draft.context == [attachment])
		#expect(fixture.store.model.composerCommands.planModes[fixture.conversation] == .plan)
	}

	@Test
	func barePlanUpdatesSettingsWithoutStartingModelTurn() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/plan")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		#expect(fixture.draft == original)
		#expect(fixture.service.settingsRequests.first?.id == fixture.service.base.thread.id)
		#expect(fixture.service.settingsRequests.first?.settings.collaborationMode?.mode == .plan)
		#expect(fixture.service.base.turnStartCount == 0)
		#expect(!fixture.state.currentSnapshot.canSend)
		fixture.service.finishSettings()
		#expect(await operation.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingSettings == nil)
		#expect(fixture.store.model.composerCommands.planModes[fixture.conversation] == .plan)
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.draft.context == [attachment])
		#expect(fixture.state.currentSnapshot.canSend)
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func compactReservesOwnerBeforeObserversAndWaitsForTerminalEvidenceAfterAck() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/compact")
		var reservationObserved = false
		fixture.store.observe
		{
			model in
			guard let pending = model.composerCommands.pendingTurn
			else
			{
				return
			}
			#expect(model.execution.owner?.submission
				.isSameRequest(as: pending.request.context) == true)
			#expect(fixture.store.operation(for: pending.request.context) != nil)
			#expect(!WorkspaceEligibility(model: model).canSend)
			#expect(fixture.store.lifecycleObservation.managementInProgress)
			reservationObserved = true
		}
		let operation = try #require(fixture.state.inputs.send())
		#expect(reservationObserved)
		try #require(await fixture.eventually
		{
			fixture.service.pendingCompact != nil
		})
		#expect(fixture.draft.text == "/compact")
		fixture.service.finishCompact()
		#expect(await operation.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingTurn?.transportFinished == true)
		#expect(fixture.store.model.composerCommands.pendingTurn?.terminalObserved == false)
		#expect(fixture.store.model.execution.state.isBusy)
		#expect(!fixture.state.currentSnapshot.canSend)
		#expect(fixture.draft.text.isEmpty)
		fixture.service.base.emit(.contextCompacted(
			threadId: fixture.service.base.thread.id,
			turnId: "compact-turn"
		))
		try #require(await fixture.eventually
		{
			fixture.state.currentSnapshot.canSend
		})
		#expect(fixture.store.model.composerCommands.pendingTurn == nil)
		#expect(fixture.store.model.execution.submissionRequest == nil)
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func reviewEventsBeforeAcknowledgementRetainIndependentCommandExitBarrier() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/review uncommitted")
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingReview != nil
		})
		let thread = fixture.service.base.thread.id
		let running = fixture.turn(
			id: "review-turn",
			status: "inProgress"
		)
		fixture.service.base.emit(.turnStarted(
			threadId: thread,
			turn: running
		))
		let command: [String: Any] = ["id": "review-command",
										"type": "commandExecution",
										"command": "git diff",
										"status": "inProgress"]
		fixture.service.base.emit(.itemStarted(
			threadId: thread,
			turnId: running.id,
			item: CodexItem(json: command)!
		))
		try #require(await fixture.eventually
		{
			fixture.store.model.execution.commandLifetime.hasPendingCommands
		})
		#expect(fixture.store.model.execution.owner?.submission.turnID == running.id)
		#expect(fixture.store.model.composerCommands.pendingTurn?.transportFinished == false)
		#expect(fixture.service.reviewRequests.first?.target == .uncommittedChanges)
		#expect(fixture.service.reviewRequests.first?.delivery == .inline)
		let completed = fixture.turn(
			id: running.id,
			status: "completed",
			items: [command]
		)
		fixture.service.base.savedTurns = [completed]
		fixture.service.base.emit(.turnCompleted(
			threadId: thread,
			turn: completed
		))
		try #require(await fixture
			.eventually
			{
				fixture.store.model.execution.agentOutcome == .completed
			})
		#expect(!fixture.state.currentSnapshot.canSend)
		#expect(fixture.store.model.execution.commandLifetime.hasPendingCommands)
		fixture.service.finishReview(running)
		#expect(await operation.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingTurn == nil)
		#expect(fixture.store.model.execution.commandLifetime.hasPendingCommands)
		#expect(!fixture.state.currentSnapshot.canSend)
		var exited = command
		exited["status"] = "completed"
		exited["exitCode"] = 0
		fixture.service.base.savedTurns = [fixture.turn(
			id: running.id,
			status: "completed",
			items: [exited]
		)]
		fixture.service.base.emit(.itemCompleted(
			threadId: thread,
			turnId: running.id,
			item: CodexItem(json: exited)!
		))
		try #require(await fixture.eventually
		{
			fixture.state.currentSnapshot.canSend
		})
		#expect(!fixture.store.model.execution.commandLifetime.hasPendingCommands)
		#expect(fixture.store.model.execution.submissionRequest == nil)
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func replayOfPreviousTurnCannotClaimOrFinishReservedCompaction() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		let old = fixture.turn(
			id: "previous-turn",
			status: "completed"
		)
		fixture.service.base.savedTurns = [old]
		try await fixture.start()
		fixture.state.inputs.updateDraft("/compact")
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingCompact != nil
		})
		let request = try #require(fixture.store.model.composerCommands.pendingTurn?.request
			.context)
		let thread = fixture.service.base.thread.id
		fixture.service.base.emit(.turnStarted(
			threadId: thread,
			turn: fixture.turn(
				id: old.id,
				status: "inProgress"
			)
		))
		fixture.service.base.emit(.turnCompleted(
			threadId: thread,
			turn: old
		))
		await Task.yield()
		#expect(fixture.store.model.execution.owner?.submission.isSameRequest(as: request) == true)
		#expect(fixture.store.model.execution.owner?.submission.turnID == nil)
		#expect(fixture.store.model.execution.activeTurnID == nil)
		#expect(fixture.store.model.composerCommands.pendingTurn?.terminalObserved == false)
		#expect(fixture.store.model.execution.state.isBusy)
		#expect(!fixture.state.currentSnapshot.canSend)
		fixture.service.finishCompact()
		#expect(await operation.wait() == .finished)
		#expect(!fixture.state.currentSnapshot.canSend)
		fixture.service.base.emit(.contextCompacted(
			threadId: thread,
			turnId: "new-compact-turn"
		))
		try #require(await fixture.eventually
		{
			fixture.state.currentSnapshot.canSend
		})
		#expect(fixture.store.model.composerCommands.pendingTurn == nil)
	}

	@Test(arguments: ["/compact", "/review uncommitted"])
	func terminalHistoryBeforeLateAckDoesNotOrphanTransportRequest(command: String) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft(command)
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingCompact != nil || fixture.service.pendingReview != nil
		})
		let request = try #require(fixture.store.model.composerCommands.pendingTurn?.request)
		let thread = fixture.service.base.thread.id
		let running = fixture.turn(
			id: "early-terminal",
			status: "inProgress"
		)
		let marker = command == "/compact" ? "contextCompaction" : "enteredReviewMode"
		let completed = fixture.turn(
			id: running.id,
			status: "completed",
			items: [
				["id": "command-marker", "type": marker],
			]
		)
		fixture.service.base.savedTurns = [completed]
		fixture.service.base.emit(.turnStarted(
			threadId: thread,
			turn: running
		))
		let reads = fixture.service.base.readThreadCount
		fixture.service.base.emit(.turnCompleted(
			threadId: thread,
			turn: completed
		))
		try #require(await fixture.eventually
		{
			fixture.service.base.readThreadCount > reads
				&& fixture.store.model.conversations.pendingReads.isEmpty
		})
		#expect(fixture.store.model.composerCommands.pendingTurn?.request.context == request
			.context)
		#expect(fixture.store.model.composerCommands.pendingTurn?.terminalObserved == true)
		#expect(fixture.store.model.composerCommands.pendingTurn?.transportFinished == false)
		#expect(fixture.store.model.execution.submissionRequest?
			.isSameRequest(as: request.context) == true)
		#expect(!fixture.state.currentSnapshot.canSend)
		if command == "/compact"
		{
			fixture.service.finishCompact()
		}
		else
		{
			fixture.service.finishReview(running)
		}
		#expect(await operation.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingTurn == nil)
		#expect(fixture.store.model.execution.submissionRequest == nil)
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.state.currentSnapshot.canSend)
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func localPresentationsRetainDraftUntilAcknowledgedAndNeverStartLiteralModelTurns() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		let attachment = try fixture.attachFile()
		var requests: [SlashCommandPresentationRequest] = []
		fixture.store.observePublications
		{
			publication in
			for command in publication.commands
			{
				if case .slashCommand(let request) = command
				{
					requests.append(request)
				}
			}
		}
		for command in ["/status",
						"/model",
						"/reasoning",
						"/permissions",
						"/skills",
						"/mention",
						"/diff",
						"/copy",
						"/resume",
						"/review"]
		{
			fixture.state.inputs.updateDraft(command)
			let original = fixture.draft
			let count = requests.count
			_ = fixture.state.inputs.send()
			#expect(requests.count == count + 1)
			let request = try #require(requests.last)
			#expect(request.draft == original)
			#expect(fixture.draft == original)
			fixture.state.inputs.acknowledgeSlashCommand(request)
			#expect(fixture.draft.text.isEmpty)
			#expect(fixture.draft.context == [attachment])
		}
		#expect(fixture.service.base.turnStartCount == 0)
		#expect(fixture.service.base.steeredTurns.isEmpty)
		#expect(fixture.service.forkRequests.isEmpty)
		#expect(fixture.service.reviewRequests.isEmpty)
		#expect(fixture.service.compactRequests.isEmpty)
	}

	@Test(arguments: ["draft", "thread", "generation"])
	func stalePresentationAcknowledgementCannotConsumeAReplacementContext(
		change: String
	) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		var captured: SlashCommandPresentationRequest?
		fixture.store.observePublications
		{
			publication in
			for command in publication.commands
			{
				if case .slashCommand(let request) = command
				{
					captured = request
				}
			}
		}
		fixture.state.inputs.updateDraft("/status")
		_ = fixture.state.inputs.send()
		let request = try #require(captured)
		switch change
		{
		case "draft":
			fixture.state.inputs.updateDraft("Intermediate edit")
			fixture.state.inputs.updateDraft("/status")
		case "thread":
			fixture.service.base.otherThread = fixture.detail(id: "other-thread").summary
			_ = await fixture.state.inputs.selectThread("other-thread")?.wait()
			fixture.state.inputs.updateDraft("/status")
		default:
			await fixture.state.inputs.connect()
			try #require(fixture.store.model.connection.generation != request.context.generation)
		}
		let currentConversation = fixture.store.model.conversations.selectedConversation
		let replacement = fixture.store.model.composer.drafts[currentConversation]
		fixture.state.inputs.acknowledgeSlashCommand(request)
		#expect(fixture.store.model.composer.drafts[currentConversation] == replacement)
		#expect(fixture.draft.text == "/status")
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test(arguments: ["Ordinary prompt", "//status", "//plan hello", "/Users/example/source.swift"])
	func sendPreservesOrdinaryTextAndRemovesOnlyTheEscapeSlash(source: String) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft(source)
		_ = try fixture.attachFile()
		let operation = try #require(fixture.state.inputs.send())
		#expect(await operation.wait() == .finished)
		let expected = source.hasPrefix("//") ? String(source.dropFirst()) : source
		let inputs = try #require(fixture.service.base.sentInputRequests.first)
		guard case .text(let sentText) = inputs.first
		else
		{
			Issue.record("Expected submitted text before the attachment")
			return
		}
		#expect(sentText.hasPrefix(expected))
		#expect(inputs.count == 2)
		#expect(inputs[1] == .mention(
			name: "evidence.txt",
			path: fixture.project.appendingPathComponent("evidence.txt").path
		))
		#expect(fixture.service.turnModes.count == 1)
		#expect(fixture.service.turnModes[0] == nil)
		#expect(fixture.store.model.composerCommands.error == nil)
	}

	@Test
	func unknownSendAndSteerCommandsPreserveAttachmentsWithoutModelRequests() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/unknown-command arguments")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		#expect(fixture.state.inputs.send() == nil)
		#expect(fixture.draft == original)
		#expect(fixture.store.model.composerCommands.error?.contains("Unknown command") == true)
		#expect(fixture.service.base.turnStartCount == 0)
		fixture.state.inputs.updateDraft("Start the fixture turn")
		let operation = try #require(fixture.state.inputs.send())
		#expect(await operation.wait() == .finished)
		fixture.state.inputs.updateDraft("/unknown-command arguments")
		fixture.state.inputs.addDraftContext(attachment)
		let steeringDraft = fixture.draft
		fixture.state.inputs.steer(steeringDraft.text)
		#expect(fixture.draft == steeringDraft)
		#expect(fixture.service.base.steeredTurns.isEmpty)
		#expect(fixture.service.base.turnStartCount == 1)
		#expect(fixture.store.model.composerCommands.error?.contains("Unknown command") == true)
	}

	@Test(arguments: ["Ordinary steering", "//status"])
	func steerRoutesTextAndEscapeThroughTheActiveTurn(source: String) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("Start the fixture turn")
		let operation = try #require(fixture.state.inputs.send())
		#expect(await operation.wait() == .finished)
		fixture.state.inputs.updateDraft(source)
		fixture.state.inputs.steer(source)
		try #require(await fixture.eventually
		{
			fixture.service.base.steeredTurns.count == 1
		})
		#expect(fixture.service.base.steeredTurns.first?
			.text == (source == "//status" ? "/status" : source))
		#expect(fixture.service.base.steeredTurns.first?.threadID == fixture.service.base.thread.id)
		#expect(fixture.service.base.steeredTurns.first?.turnID == fixture.service.base.nextTurn.id)
		#expect(fixture.service.base.turnStartCount == 1)
	}

	@Test(arguments: [true, false])
	func fastModeUsesAdvertisedTierAndRejectsModelsWithoutThatCapability(
		supported: Bool
	) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		fixture.service.base.availableModels = [ModelOption(json: [
			"model": "fixture-model",
			"isDefault": true,
			"serviceTiers": supported ? [["id": "express",
											"name": "Fast",
											"description": "Fixture fast tier"]] : [],
		])!]
		try await fixture.start()
		fixture.state.inputs.updateDraft("/fast on")
		_ = fixture.state.inputs.send()
		#expect(fixture.service.base.turnStartCount == 0)
		if !supported
		{
			#expect(fixture.draft.text == "/fast on")
			#expect(fixture.store.model.composerCommands.error != nil)
			#expect(!fixture.store.model.preferences.runPreferences.fastMode)
			return
		}
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.store.model.preferences.runPreferences.fastMode)
		fixture.state.inputs.updateDraft("Use the advertised fast tier")
		let operation = try #require(fixture.state.inputs.send())
		#expect(await operation.wait() == .finished)
		#expect(fixture.service.turnServiceTiers == ["express"])
		#expect(fixture.service.base.capturedTurnPreferences.first?.preferences.fastMode == true)
		#expect(fixture.service.base.turnStartCount == 1)
	}

	@Test
	func disconnectForkRetainsTypedUncertaintyUntilResume() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/fork")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingFork != nil
		})
		let previousGeneration = fixture.store.model.connection.generation
		fixture.service.base.emitDisconnect("Fixture connection lost")
		#expect(fixture.store.model.connection.generation > previousGeneration)
		#expect(fixture.draft == original)
		#expect(fixture.store.model.composerCommands.pendingFork == nil)
		#expect(fixture.store.model.composerCommands.uncertainFork != nil)
		fixture.service.failForkAfterDisconnect()
		_ = await operation.wait()
		#expect(fixture.store.model.composerCommands.blocksNewWork)
		#expect(fixture.draft == original)
		let recovered = fixture.detail(id: "recovered-fork")
		fixture.service.base.otherThread = recovered.summary
		await fixture.state.inputs.connect()
		#expect(fixture.store.model.connection.isConnected)
		#expect(!WorkspaceEligibility(model: fixture.store.model).canSend)
		var presentation: SlashCommandPresentationRequest?
		fixture.store.observePublications
		{
			publication in
			for value in publication.commands
			{
				if case .slashCommand(let request) = value
				{
					presentation = request
				}
			}
		}
		_ = fixture.state.inputs.send()
		try #require(await fixture.eventually
		{
			presentation != nil
		})
		let request = try #require(presentation)
		#expect(request.context.generation == fixture.store.model.connection.generation)
		#expect(request.draft == original)
		fixture.state.inputs.recoverFork(
			request,
			choice: .resume(threadID: recovered.summary.id)
		)
		try #require(await fixture.eventually
		{
			fixture.store.model.conversations
				.selectedConversation == .thread(recovered.summary.id)
				&& fixture.store.model.conversations.pendingSelection == nil
		})
		#expect(fixture.store.model.composerCommands.uncertainFork == nil)
		#expect(fixture.service.forkRequests.count == 1)
		try #require(await fixture.eventually
		{
			fixture.state.currentSnapshot.canSend
		})
		#expect(!fixture.store.model.composerCommands.blocksNewWork)
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.draft.context == [attachment])
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func disconnectPlanRetainsTypedUncertaintyUntilConfirmedRetry() async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/plan")
		let attachment = try fixture.attachFile()
		let original = fixture.draft
		let operation = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		let previousGeneration = fixture.store.model.connection.generation
		fixture.service.base.emitDisconnect("Fixture connection lost")
		#expect(fixture.store.model.connection.generation > previousGeneration)
		#expect(fixture.draft == original)
		#expect(fixture.store.model.composerCommands.pendingSettings?.outcomeUncertain == true)
		fixture.service.failSettingsAfterDisconnect()
		_ = await operation.wait()
		#expect(fixture.store.model.composerCommands.blocksNewWork)
		#expect(fixture.draft == original)
		await fixture.state.inputs.connect()
		#expect(fixture.store.model.connection.isConnected)
		#expect(!WorkspaceEligibility(model: fixture.store.model).canSend)
		var presentation: SlashCommandPresentationRequest?
		fixture.store.observePublications
		{
			publication in
			for value in publication.commands
			{
				if case .slashCommand(let request) = value
				{
					presentation = request
				}
			}
		}
		_ = fixture.state.inputs.send()
		try #require(await fixture.eventually
		{
			presentation != nil
		})
		let request = try #require(presentation)
		#expect(request.context.generation == fixture.store.model.connection.generation)
		#expect(request.draft == original)
		let recovery = try #require(fixture.state.inputs.retryPlanSettings(
			request,
			mode: .plan
		))
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		fixture.service.finishSettings()
		#expect(await recovery.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingSettings == nil)
		#expect(fixture.store.model.composerCommands.planModes[fixture.conversation] == .plan)
		#expect(fixture.service.settingsRequests.count == 2)
		try #require(await fixture.eventually
		{
			fixture.state.currentSnapshot.canSend
		})
		#expect(!fixture.store.model.composerCommands.blocksNewWork)
		#expect(fixture.draft.text.isEmpty)
		#expect(fixture.draft.context == [attachment])
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test(arguments: ["/fork", "/compact", "/review uncommitted", "/plan"])
	func observerShutdownCancelsReservedCommandBeforeAnyBackendCall(command: String) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft(command)
		try await fixture.store.awaitAcceptedPersistence()
		try await fixture.store.drainPersistence()
		try #require(await fixture.eventually
		{
			fixture.store.runningOperationCount == 0
		})
		let reads = fixture.service.base.readThreadCount
		var captured: WorkspaceOperationHandle?
		fixture.store.observe
		{
			model in
			let context = model.composerCommands.pendingFork?.context
				?? model.composerCommands.pendingTurn?.request.context
				?? model.composerCommands.pendingSettings?.request.context
			guard let context
			else
			{
				return
			}
			captured = fixture.store.operation(for: context)
			#expect(captured != nil)
			#expect(fixture.store.runningOperationCount == 1)
			fixture.store.shutdown()
		}
		_ = fixture.state.inputs.send()
		let handle = try #require(captured)
		#expect(await handle.wait() == .cancelled)
		await Task.yield()
		#expect(fixture.store.isRetired)
		#expect(fixture.store.runningOperationCount == 0)
		#expect(fixture.service.base.readThreadCount == reads)
		#expect(fixture.service.forkRequests.isEmpty)
		#expect(fixture.service.compactRequests.isEmpty)
		#expect(fixture.service.reviewRequests.isEmpty)
		#expect(fixture.service.settingsRequests.isEmpty)
		#expect(fixture.service.base.turnStartCount == 0)
	}

	@Test
	func rejectedExplicitPlanRetryPreservesTheOriginalUnknownOutcomeUntilAConfirmedRetry(
	) async throws
	{
		let fixture = try ComposerCommandRuntimeHarness()
		defer
		{
			fixture.close()
		}
		try await fixture.start()
		fixture.state.inputs.updateDraft("/plan")
		let original = fixture.draft
		let initial = try #require(fixture.state.inputs.send())
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		fixture.service.failSettingsAfterDisconnect()
		_ = await initial.wait()
		#expect(fixture.store.model.composerCommands.pendingSettings?.outcomeUncertain == true)
		var presentation: SlashCommandPresentationRequest?
		fixture.store.observePublications
		{
			publication in
			for value in publication.commands
			{
				if case .slashCommand(let request) = value
				{
					presentation = request
				}
			}
		}
		_ = fixture.state.inputs.send()
		let request = try #require(presentation)
		let rejected = try #require(fixture.state.inputs.retryPlanSettings(
			request,
			mode: .plan
		))
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		fixture.service.rejectSettingsRetry()
		_ = await rejected.wait()
		#expect(fixture.store.model.composerCommands.pendingSettings?.outcomeUncertain == true)
		#expect(fixture.store.model.composerCommands.pendingSettings?.mode.mode == .plan)
		#expect(fixture.store.model.execution.needsReconciliation)
		#expect(!WorkspaceEligibility(model: fixture.store.model).canSend)
		#expect(fixture.draft == original)
		presentation = nil
		_ = fixture.state.inputs.send()
		let current = try #require(presentation)
		let confirmed = try #require(fixture.state.inputs.retryPlanSettings(
			current,
			mode: .plan
		))
		try #require(await fixture.eventually
		{
			fixture.service.pendingSettings != nil
		})
		fixture.service.finishSettings()
		#expect(await confirmed.wait() == .finished)
		#expect(fixture.store.model.composerCommands.pendingSettings == nil)
		#expect(fixture.store.model.composerCommands.planModes[fixture.conversation] == .plan)
		#expect(fixture.state.currentSnapshot.canSend)
		#expect(fixture.service.settingsRequests.count == 3)
		#expect(fixture.service.base.turnStartCount == 0)
	}
}
