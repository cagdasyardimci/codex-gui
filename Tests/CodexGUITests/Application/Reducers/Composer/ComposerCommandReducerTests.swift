import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ComposerCommandReducerTests
{
	@Test(arguments: [
		"workspace",
		"checkout",
		"generation",
		"selection",
		"text",
		"revision",
		"lifetime",
		"attachment",
		"thread",
	])
	func staleCapturedCommandCannotChangePreferencesOrConsumeDraft(_ staleField: String) throws
	{
		var (model, request) = try fixture("/fast on")
		switch staleField
		{
		case "workspace":
			model.identity = WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: model.identity.canonicalCheckoutPath
			)
		case "checkout":
			model.identity = WorkspaceIdentity(
				sessionID: model.identity.sessionID,
				canonicalCheckoutPath: "/tmp/other-checkout"
			)
		case "generation": model.connection.generation += 1
		case "selection": model.conversations.selectedConversation = .thread("other")
		case "text": model.composer.drafts[request.conversation]?.text = "later draft"
		case "revision": model.composer.drafts[request.conversation]?.revision += 1
		case "lifetime": model.composer.drafts[request.conversation]?.lifetime += 1
		case "attachment": model.composer.drafts[request.conversation]?.context = []
		case "thread":
			var context = request.context
			context.threadID = "other"
			request = replacingContext(
				request,
				with: context
			)
		default: Issue.record("Unknown stale field")
		}
		let before = model.composer.drafts
		let reduced = requestCommand(
			request,
			model: &model
		)
		#expect(!model.preferences.runPreferences.fastMode)
		#expect(model.composer.drafts == before)
		#expect(reduced.effects.isEmpty)
		#expect(reduced.presentationCommands.isEmpty)
		#expect(!model.composerCommands.blocksNewWork)
	}

	@Test func currentCommandConsumesOnlyItsTextAndRetainsAttachments() throws
	{
		var (model, request) = try fixture("/fast on")
		_ = requestCommand(
			request,
			model: &model
		)
		#expect(model.preferences.runPreferences.fastMode)
		#expect(model.composer.drafts[request.conversation]?.text == "")
		#expect(model.composer.drafts[request.conversation]?.context == request.draft.context)
		#expect(model.composer.drafts[request.conversation]?.revision == request.draft.revision + 1)
		#expect(model.composer.drafts[request.conversation]?.lifetime == request.draft.lifetime)
	}

	@Test func forkIsAdmittedOnlyFromSourceCheckout() throws
	{
		var (source, sourceRequest) = try fixture("/fork")
		let accepted = requestCommand(
			sourceRequest,
			model: &source
		)
		#expect(source.composerCommands.pendingFork?.context == sourceRequest.context)
		#expect(accepted.effects.count == 1)
		guard case .forkConversation(let effectRequest) = accepted.effects.first
		else
		{
			Issue.record("Expected captured fork effect")
			return
		}
		#expect(effectRequest.context == sourceRequest.context)
		#expect(source.composer.drafts[sourceRequest.conversation] == sourceRequest.draft)

		for managed in [false, true]
		{
			var (model, request) = try fixture("/fork")
			if managed
			{
				let workspace = managedWorkspace(model)
				model.lifecycle.managedWorkspace = workspace
				model.lifecycle.owner = .managed(
					workspaceID: workspace.id,
					sessionID: model.identity.sessionID
				)
			}
			else
			{
				model.conversations.boundThreadID = "thread"
			}
			let denied = requestCommand(
				request,
				model: &model
			)
			#expect(denied.effects.isEmpty)
			#expect(model.composerCommands.pendingFork == nil)
			#expect(model.composerCommands.error?.contains("source checkout") == true)
			#expect(model.composer.drafts[request.conversation] == request.draft)
		}
	}

	@Test func reconnectAndAnotherForkDoNotReleaseAnUncertainForkOutcome() throws
	{
		var (model, request) = try fixture("/fork")
		_ = requestCommand(
			request,
			model: &model
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.forkFinished(
				request,
				.failed(OperationFailure(
					message: "lost fork reply",
					outcomeIsUncertain: true
				))
			))
		)
		#expect(model.composerCommands.uncertainFork == request.context)
		model.connection.generation += 1
		_ = ComposerCommandReducer.reduce(
			&model,
			.connection(.projectOpened(
				model.identity,
				selectedThreadID: "thread"
			))
		)
		#expect(model.composerCommands.uncertainFork == request.context)
		let current = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
		let retry = replacingContext(
			request,
			with: current
		)
		let denied = requestCommand(
			retry,
			model: &model
		)
		#expect(!denied.effects.contains
		{
			if case .forkConversation = $0
			{
				return true
			}
			return false
		})
		#expect(model.composerCommands.pendingFork == nil)
		#expect(model.composerCommands.uncertainFork == request.context)
		#expect(model.composerCommands.blocksNewWork)
		#expect(model.composer.drafts[request.conversation] == request.draft)
	}

	@Test(arguments: ["available", "missing", "foreign"])
	func continueOriginalTargetsTheForkOriginAfterSelectionChanges(_ availability: String) throws
	{
		var (model, original) = try fixture("/fork")
		_ = requestCommand(
			original,
			model: &model
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.forkFinished(
				original,
				.failed(OperationFailure(
					message: "lost reply",
					outcomeIsUncertain: true
				))
			))
		)
		model.conversations.selectedConversation = .thread("selected-b")
		model.conversations.threads.append(detail(
			id: "selected-b",
			turns: []
		).summary)
		model.composer.drafts[.thread("selected-b")] = original.draft
		if availability != "available"
		{
			model.conversations.threads.removeAll
			{
				$0.id == "thread"
			}
			if availability == "foreign"
			{
				model.conversations.threads.append(ThreadSummary(json: [
					"id": "thread",
					"cwd": "/tmp/other-checkout",
				])!)
			}
		}
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID(),
				threadID: "selected-b"
			),
			invocation: original.invocation,
			conversation: .thread("selected-b"),
			draft: original.draft
		)
		model.composerCommands.forkRecoveryPresentation = request
		model.composerCommands.forkRecoveryListReady = true
		let reduced = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.forkRecoveryRequested(
				request,
				.continueOriginal
			))
		)
		if availability == "available"
		{
			#expect(model.composerCommands.uncertainFork == nil)
			#expect(model.conversations.selectedConversation == original.conversation)
			#expect(model.conversations.pendingSelection?.threadID == "thread")
			#expect(model.conversations.pendingSelection?.threadID != request.context.threadID)
			#expect(reduced.effects.contains
			{
				if case .readConversationHistory(let operation) = $0
				{
					return operation.context.threadID == "thread" && operation.purpose == .selection
				}
				return false
			})
		}
		else
		{
			#expect(model.composerCommands.uncertainFork == original.context)
			#expect(model.composerCommands.blocksNewWork)
			#expect(model.conversations.pendingSelection == nil)
			#expect(model.composer.drafts[request.conversation] == request.draft)
			#expect(reduced.effects.isEmpty)
		}
	}

	@Test(arguments: ["/delete", "/permissions full", "/permissions", "/rename"])
	func dialogCommandsRetainDraftAndRequirePresentationAcknowledgement(_ text: String) throws
	{
		var (model, request) = try fixture(text)
		let reduced = requestCommand(
			request,
			model: &model
		)
		#expect(reduced.effects.isEmpty)
		#expect(model.conversations.pendingManagement == nil)
		#expect(model.preferences.runPreferences.approvalMode == .askForApproval)
		#expect(model.composer.drafts[request.conversation] == request.draft)
		guard case .slashCommand(let presented) = reduced.presentationCommands.first
		else
		{
			Issue.record("Expected native command presentation")
			return
		}
		#expect(presented.context == request.context)
		#expect(presented.draft == request.draft)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.acknowledged(presented))
		)
		#expect(model.composer.drafts[request.conversation]?.text == "")
		#expect(model.composer.drafts[request.conversation]?.context == request.draft.context)
	}

	@Test func delayedDialogAcknowledgementCannotEraseAnEditedDraft() throws
	{
		var (model, request) = try fixture("/delete")
		_ = requestCommand(
			request,
			model: &model
		)
		model.composer.drafts[request.conversation]?.text = "keep this later message"
		model.composer.drafts[request.conversation]?.revision += 1
		let before = model.composer.drafts[request.conversation]
		let reduced = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.acknowledged(request))
		)
		#expect(model.composer.drafts[request.conversation] == before)
		#expect(reduced.effects.isEmpty)
	}

	@Test func unrelatedAndHistoricalTerminalEventsCannotSettleCompactOwner() throws
	{
		var (model, request) = try fixture("/compact")
		_ = try startTurn(
			request,
			model: &model
		)
		for event in [
			AppServerEvent.contextCompacted(
				threadId: "other",
				turnId: "new-turn"
			),
			.contextCompacted(
				threadId: "thread",
				turnId: "old-turn"
			),
			.turnCompleted(
				threadId: "other",
				turn: turn("new-turn")
			),
			.turnCompleted(
				threadId: "thread",
				turn: turn("unobserved-turn")
			),
		]
		{
			observe(
				event,
				model: &model
			)
			#expect(model.composerCommands.pendingTurn?.terminalObserved == false)
			#expect(model.execution.owner?.submission == request.context)
			#expect(model.execution.agentOutcome == nil)
		}
		_ = ComposerCommandReducer.reduceDomainEvent(
			&model,
			.historyAccepted(
				detail(
					id: "other",
					turns: [turn("new-turn")]
				),
				threadID: "other"
			)
		)
		#expect(model.composerCommands.pendingTurn?.request.context == request.context)
	}

	@Test func staleTransportAcknowledgementCannotReleaseACommandReservation() throws
	{
		var (model, request) = try fixture("/compact")
		let operation = try startTurn(
			request,
			model: &model
		)
		let staleContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
		let stale = ComposerCommandTurnOperation(
			request: replacingContext(
				request,
				with: staleContext
			),
			kind: operation.kind,
			previousTurnIDs: operation.previousTurnIDs
		)
		let reduced = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.compactAcknowledged(
				stale,
				.succeeded(())
			))
		)
		#expect(model.composerCommands.pendingTurn?.transportFinished == false)
		#expect(model.execution.owner?.submission == request.context)
		#expect(model.composer.drafts[request.conversation] == request.draft)
		#expect(reduced.effects.isEmpty)
	}

	@Test func uncertainCompactFailureKeepsOwnerUntilReconciliation() throws
	{
		var (model, request) = try fixture("/compact")
		let operation = try startTurn(
			request,
			model: &model
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.compactAcknowledged(
				operation,
				.failed(OperationFailure(
					message: "lost transport",
					outcomeIsUncertain: true
				))
			))
		)
		#expect(model.execution.hasUncertainRequest)
		#expect(model.execution.needsReconciliation)
		#expect(model.composerCommands.blocksNewWork)
		#expect(model.execution.owner?.submission.isSameRequest(as: request.context) == true)
		#expect(model.composer.drafts[request.conversation] == request.draft)
	}

	@Test func settingsObservationBeforeAcknowledgementDoesNotLoseCapturedPlanChange() throws
	{
		var (model, request) = try fixture("/plan")
		_ = requestCommand(
			request,
			model: &model
		)
		let operation = try #require(model.composerCommands.pendingSettings)
		observe(
			.threadSettingsUpdated(
				threadId: "thread",
				settings: settings(.plan)
			),
			model: &model
		)
		#expect(model.composerCommands.planModes[request.conversation] == .plan)
		#expect(model.composerCommands.pendingSettings?.request.context == request.context)
		#expect(model.composer.drafts[request.conversation] == request.draft)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				operation,
				.succeeded(())
			))
		)
		#expect(model.composerCommands.pendingSettings == nil)
		#expect(model.composerCommands.planModes[request.conversation] == .plan)
		#expect(model.composer.drafts[request.conversation]?.text == "")
	}

	@Test func uncertainPlanChangeRecoversFromSettingsEventWithoutFlippingDesiredMode() throws
	{
		var (model, request) = try fixture("/plan")
		_ = requestCommand(
			request,
			model: &model
		)
		let operation = try #require(model.composerCommands.pendingSettings)
		#expect(operation.mode.mode == .plan)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				operation,
				.failed(OperationFailure(
					message: "lost reply",
					outcomeIsUncertain: true
				))
			))
		)
		#expect(model.composerCommands.pendingSettings?.mode.mode == .plan)
		#expect(model.execution.needsReconciliation)
		#expect(model.composer.drafts[request.conversation] == request.draft)
		#expect(!model.execution.hasUncertainRequest)
		observe(
			.turnStarted(
				threadId: "thread",
				turn: turn(
					"phone-turn",
					status: "inProgress"
				)
			),
			model: &model
		)
		#expect(model.execution.needsReconciliation)
		#expect(model.composerCommands.pendingSettings?.outcomeUncertain == true)
		observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn("phone-turn")
			),
			model: &model
		)
		#expect(model.execution.needsReconciliation)
		#expect(!WorkspaceEligibility(model: model).canSend)
		observe(
			.threadSettingsUpdated(
				threadId: "thread",
				settings: settings(.plan)
			),
			model: &model
		)
		#expect(model.composerCommands.pendingSettings == nil)
		#expect(model.composerCommands.planModes[request.conversation] == .plan)
		#expect(model.composer.drafts[request.conversation]?.text == "")
		#expect(model.composer.drafts[request.conversation]?.context == request.draft.context)
		#expect(!model.execution.needsReconciliation)
		#expect(WorkspaceEligibility(model: model).canSend)
	}

	@Test func remoteTurnPreservesDeferredStopAfterRejectedCompaction() throws
	{
		var (model, request) = try fixture("/compact")
		let operation = try startTurn(
			request,
			model: &model
		)
		let stopContext = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.stopRequested(stopContext))
		)
		#expect(model.execution.stopRequested)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.compactAcknowledged(
				operation,
				.failed(OperationFailure(
					message: "rejected before starting",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.execution.owner == nil)
		#expect(!model.execution.hasUncertainRequest)
		_ = WorkspaceLifecycleComposition.reduceDomainEvent(
			&model,
			.backendObserved(.threadStatusChanged(
				threadId: "thread",
				status: try #require(ThreadStatus(json: ["type": "active", "activeFlags": []]))
			)),
			context: request.context
		)
		observe(
			.turnStarted(
				threadId: "thread",
				turn: turn(
					"phone-turn",
					status: "inProgress"
				)
			),
			model: &model
		)
		#expect(model.execution.stopRequested)
		#expect(model.execution.needsReconciliation)
		observe(
			.turnCompleted(
				threadId: "thread",
				turn: turn("phone-turn")
			),
			model: &model
		)
		#expect(model.execution.needsReconciliation)
		#expect(!WorkspaceEligibility(model: model).canSend)
	}

	@Test(arguments: ["plan", "default"])
	func explicitPlanRetryUsesDesiredModeAndRejectsThePreviousTransportReply(
		_ rawMode: String
	) throws
	{
		var (model, request) = try fixture("/plan")
		_ = requestCommand(
			request,
			model: &model
		)
		let original = try #require(model.composerCommands.pendingSettings)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				original,
				.failed(OperationFailure(
					message: "lost reply",
					outcomeIsUncertain: true
				))
			))
		)
		// A displayed local mode must not turn an explicit recovery choice into a toggle.
		model.composerCommands.planModes[request.conversation] = .plan
		let desired = try #require(CollaborationModeKind(rawValue: rawMode))
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
		let retry = ComposerCommandSettingsOperation(
			request: replacingContext(
				request,
				with: context
			),
			mode: CollaborationMode(
				mode: desired,
				model: "test-model",
				reasoningEffort: "medium"
			)
		)
		let reduced = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsRetryRequested(retry))
		)
		#expect(reduced.effects.count == 1)
		#expect(model.composerCommands.pendingSettings?.request.context == context)
		#expect(model.composerCommands.pendingSettings?.mode.mode == desired)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				original,
				.succeeded(())
			))
		)
		#expect(model.composerCommands.pendingSettings?.request.context == context)
		#expect(model.composer.drafts[request.conversation] == request.draft)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				retry,
				.succeeded(())
			))
		)
		#expect(model.composerCommands.pendingSettings == nil)
		#expect(model.composerCommands.planModes[request.conversation] == desired)
		#expect(model.composer.drafts[request.conversation]?.text == "")
		#expect(!model.execution.needsReconciliation)
	}

	@Test(arguments: [false, true])
	func planModeFollowsPreparedThreadWithoutClearingARenewedNewChat(_ renewed: Bool) throws
	{
		var (model, original) = try fixture("/plan")
		model.conversations.selectedConversation = .newChat
		var draft = original.draft
		draft.text = "Please plan this change"
		model.composer.drafts[.newChat] = draft
		model.composerCommands.planModes[.newChat] = .plan
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .newChat,
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID(),
			collaborationMode: CollaborationMode(
				mode: .plan,
				model: "test-model",
				reasoningEffort: "medium"
			)
		)
		model.execution.owner = ExecutionOwner(submission: context)
		model.execution.submissionRequest = context
		model.execution.state = .running
		model.composer.pendingSubmissions[context.requestID] = submission
		if renewed
		{
			model.composer.drafts[.newChat]?.lifetime += 1
			model.composerCommands.planModes[.newChat] = .default
		}
		let prepared = PreparedSubmission(
			submission: submission,
			thread: detail(
				id: "adopted-thread",
				turns: []
			)
		)
		let action = WorkspaceAction.execution(.submissionPrepared(
			context,
			.succeeded(prepared)
		))
		_ = ExecutionReducer.reduce(
			&model,
			action
		)
		let composer = ComposerReducer.reduce(
			&model,
			action
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			action
		)
		for event in composer.domainEvents
		{
			_ = ComposerCommandReducer.reduceDomainEvent(
				&model,
				event
			)
		}
		#expect(model.composerCommands.planModes[.thread("adopted-thread")] == .plan)
		if renewed
		{
			#expect(model.composerCommands.planModes[.newChat] == .default)
			#expect(model.conversations.selectedConversation == .newChat)
		}
		else
		{
			#expect(model.composerCommands.planModes[.newChat] == nil)
			#expect(model.conversations.selectedConversation == .thread("adopted-thread"))
			model.execution.state = .completed
			model.execution.submissionRequest = nil
			let conversation = ConversationKey.thread("adopted-thread")
			model.composer.drafts[conversation]?.text = "/plan"
			let adoptedDraft = try #require(model.composer.drafts[conversation])
			let request = SlashCommandPresentationRequest(
				context: OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID(),
					threadID: "adopted-thread"
				),
				invocation: original.invocation,
				conversation: conversation,
				draft: adoptedDraft
			)
			_ = requestCommand(
				request,
				model: &model
			)
			#expect(model.composerCommands.pendingSettings?.mode.mode == .default)
		}
	}

	@Test func localParseErrorAndLiteralAcknowledgementKeepUnsentContent() throws
	{
		var (model, request) = try fixture("/fast on")
		let literal = ComposerDraft(
			text: "//fast on",
			context: request.draft.context,
			revision: 4
		)
		model.composer.drafts[request.conversation] = literal
		let literalRequest = SlashCommandPresentationRequest(
			context: request.context,
			invocation: request.invocation,
			conversation: request.conversation,
			draft: literal
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.acknowledged(literalRequest))
		)
		#expect(model.composer.drafts[request.conversation] == literal)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.rejected(
				request.context,
				"Unknown command '/fats'."
			))
		)
		#expect(model.composerCommands.error == "Unknown command '/fats'.")
		#expect(model.composer.drafts[request.conversation] == literal)
		#expect(!model.preferences.runPreferences.fastMode)
	}

	private func fixture(_ text: String) throws -> (WorkspaceModel, SlashCommandPresentationRequest)
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/commands"
		)
		var model = WorkspaceModel(identity: identity)
		model.connection.generation = 7
		model.connection.isConnected = true
		model.execution.state = .ready
		model.lifecycle.owner = .source(sessionID: identity.sessionID)
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.threads = [detail(turns: []).summary]
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("old-turn")]
		)
		model.preferences.models = [try #require(ModelOption(json: [
			"model": "test-model",
			"isDefault": true,
			"defaultReasoningEffort": "medium",
			"serviceTiers": [["id": "priority", "name": "Fast", "description": "Test fast tier"]],
			"supportedReasoningEfforts": [
				["reasoningEffort": "medium"],
				["reasoningEffort": "high"]
			],
		]))]
		let draft = ComposerDraft(
			text: text,
			context: [ComposerContextItem(
				kind: .textExcerpt,
				title: "Retained context",
				path: "file.swift",
				excerpt: "value"
			)],
			revision: 3,
			lifetime: 2
		)
		model.composer.drafts[.thread("thread")] = draft
		guard case .command(let invocation) = SlashCommandParser.parse(text)
		else
		{
			throw FixtureFailure.invalidCommand
		}
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: identity,
				generation: 7,
				requestID: UUID(),
				threadID: "thread"
			),
			invocation: invocation,
			conversation: .thread("thread"),
			draft: draft
		)
		return (model, request)
	}

	private func requestCommand(
		_ request: SlashCommandPresentationRequest,
		model: inout WorkspaceModel
	) -> WorkspaceReduction
	{
		ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.requested(request))
		)
	}

	private func startTurn(
		_ request: SlashCommandPresentationRequest,
		model: inout WorkspaceModel
	) throws -> ComposerCommandTurnOperation
	{
		let reduced = requestCommand(
			request,
			model: &model
		)
		let commandEffects = reduced.effects.filter
		{
			switch ($0, request.invocation.id)
			{
			case (.compactConversation(let operation), .compact),
					(.startConversationReview(let operation), .review):
				return operation.request.context == request.context
			default: return false
			}
		}
		#expect(commandEffects.count == 1)
		let checkpoints = reduced.effects.compactMap
		{
			effect -> (OperationContext, [String])? in
			if case .persistExecutionRecovery(
				let context,
				let threadIDs
			) = effect
			{
				return (context, threadIDs)
			}
			return nil
		}
		#expect(checkpoints.count == 1)
		let checkpoint = try #require(checkpoints.first)
		let threadID = try #require(request.context.threadID)
		#expect(checkpoint.0.workspace == model.identity)
		#expect(checkpoint.0.generation == model.connection.generation)
		#expect(checkpoint.0.requestID == model.identity.sessionID)
		#expect(checkpoint.1 == [threadID])
		#expect(checkpoint.1 == model.executionRecoveryThreadIDs)
		#expect(reduced.effects.count == 2)
		return try #require(model.composerCommands.pendingTurn)
	}

	private func observe(
		_ event: AppServerEvent,
		model: inout WorkspaceModel
	)
	{
		let context = OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID()
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.backendObserved(
				context,
				event
			))
		)
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.backendObserved(
				context,
				event
			))
		)
	}

	private func replacingContext(
		_ request: SlashCommandPresentationRequest,
		with context: OperationContext
	) -> SlashCommandPresentationRequest
	{
		SlashCommandPresentationRequest(
			context: context,
			invocation: request.invocation,
			conversation: request.conversation,
			draft: request.draft
		)
	}

	private func turn(
		_ id: String,
		status: String = "completed",
		items: [CodexItem] = []
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: status,
			items: items,
			error: nil
		)
	}

	private func detail(
		id: String = "thread",
		turns: [CodexTurn]
	) -> ThreadDetail
	{
		ThreadDetail(
			summary: ThreadSummary(json: ["id": id, "cwd": "/tmp/commands"])!,
			turns: turns,
			nextTurnsCursor: nil
		)
	}

	private func settings(_ mode: CollaborationModeKind) -> ThreadSettings
	{
		ThreadSettings(json: [
			"model": "test-model",
			"cwd": "/tmp/commands",
			"collaborationMode": CollaborationMode(
				mode: mode,
				model: "test-model",
				reasoningEffort: "medium"
			).protocolValue,
		])!
	}

	private func managedWorkspace(_ model: WorkspaceModel) -> TaskWorkspace
	{
		TaskWorkspace(
			id: UUID(),
			taskID: "task",
			threadID: "thread",
			sourceProjectPath: "/tmp/source",
			repositoryGitDirectory: "/tmp/source/.git",
			branch: "codex/task",
			checkoutPath: "/tmp/commands",
			baseCommit: "base",
			sourceWasDirty: false,
			createdAt: Date(timeIntervalSince1970: 0),
			phase: .active
		)
	}

	private enum FixtureFailure: Error
	{
		case invalidCommand
	}
}
