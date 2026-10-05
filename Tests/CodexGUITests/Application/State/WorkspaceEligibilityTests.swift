import Foundation
import Testing
@testable import CodexGUI

@MainActor
struct WorkspaceEligibilityTests
{
	@Test func structuralEmptyDraftCapabilityDoesNotAuthorizeAnEmptyOrForgedProposal()
	{
		var model = fixture()
		model.composer.drafts[.newChat] = ComposerDraft()
		#expect(WorkspaceEligibility(model: model).canSend)
		#expect(WorkspaceSelectors(
			model: model,
			now: .distantPast
		).makeSnapshot().canSend)
		#expect(!WorkspaceEligibility(model: model).acceptsSubmission(proposal(model)))
		model = fixture()
		var forged = proposal(model)
		forged = ComposerSubmission(
			context: forged.context,
			conversation: forged.conversation,
			draft: forged.draft,
			inputs: [.text("different input")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID(),
			projectContextRevision: 0
		)
		#expect(!WorkspaceEligibility(model: model).acceptsSubmission(forged))
	}

	@Test func everyCanonicalBlockerInvalidatesCapturedEnabledSubmission()
	{
		let initial = fixture()
		let captured = proposal(initial)
		#expect(WorkspaceEligibility(model: initial).acceptsSubmission(captured))
		let blockers: [(inout WorkspaceModel) -> Void] = [
			{
				$0.connection.generation += 1
			},
			{
				$0.identity = WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: "/project"
				)
			},
			{
				$0.identity = WorkspaceIdentity(
					sessionID: $0.identity.sessionID,
					canonicalCheckoutPath: "/other"
				)
			},
			{
				$0.conversations.selectedConversation = .thread("other")
			},
			{
				$0.conversations.showingArchived = true
			},
			{
				$0.composer.drafts[.newChat]?.revision += 1
			},
			{
				$0.composer.drafts[.newChat]?.lifetime += 1
			},
			{
				$0.contextNavigation.contextRevision += 1
			},
			{
				$0.preferences.selectedModelID = "changed"
			},
			{
				$0.preferences.selectedEffort = "high"
			},
			{
				$0.preferences.runPreferences = RunPreferences(
					approvalMode: .fullAccess,
					fastMode: true
				)
			},
			{
				$0.preferences.modelListError = "catalog failed"
			},
			{
				$0.lifecycle.managedOwnershipConflict = "record replaced"
			},
			{
				$0.execution.needsReconciliation = true
			},
			{
				$0.execution.hasUncertainRequest = true
			},
			{
				$0.lifecycle.quitReservation = WorkspaceQuitReservation(
					requestID: UUID(),
					reference: WorkspaceLifecycleReducer.reference($0)
				)
			},
			{
				$0.contextNavigation.pendingContextLoad = ContextLoadOperation(
					context: captured.context,
					revision: 0
				)
			},
			{
				$0.conversations.pendingSelection = captured.context
			},
			{
				$0.conversations.pendingManagement = .archive(captured.context)
			}
		]
		for block in blockers
		{
			var model = initial
			block(&model)
			#expect(!WorkspaceEligibility(model: model).acceptsSubmission(captured))
			let result = ExecutionReducer.reduce(
				&model,
				.execution(.submissionRequested(captured))
			)
			#expect(result.effects.isEmpty)
			#expect(model.execution.owner == nil)
		}
	}

	@Test func preparationCompletionRechecksPreferencesAndReleasesRejectedInput()
	{
		var model = fixture()
		let captured = proposal(model)
		let operation = ComposerInputPreparationOperation.submission(captured)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.inputPreparationRequested(operation))
		)
		model.preferences.runPreferences = RunPreferences(
			approvalMode: .fullAccess,
			fastMode: false
		)
		let result = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.inputPreparationFinished(
				operation,
				.succeeded(captured.inputs)
			))
		)
		#expect(model.lifecycle.pendingInputPreparation == nil)
		#expect(model.execution.owner == nil)
		guard case .releaseUnsentSubmission(let released) = result.effects.first
		else
		{
			Issue.record("Expected retained input release")
			return
		}
		#expect(released.context == captured.context)
	}

	@Test func steeringRequiresCurrentOwnerTurnButAcceptsInstructionOverride()
	{
		var model = fixture()
		model.conversations.selectedConversation = .thread("owner")
		model.composer.drafts[.thread("owner")] = ComposerDraft(
			text: "editable",
			revision: 2,
			lifetime: 3
		)
		model.execution.state = .running
		model.execution.activeThreadID = "owner"
		model.execution.activeTurnID = "turn"
		let draft = ComposerDraft(
			text: "steering override",
			revision: 2,
			lifetime: 3
		)
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "owner",
			turnID: "turn"
		)
		let captured = ComposerSubmission(
			context: context,
			conversation: .thread("owner"),
			draft: draft,
			inputs: [.text("steering override")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID(),
			projectContextRevision: 0
		)
		let operation = SteeringOperation(
			context: context,
			submission: captured
		)
		#expect(WorkspaceEligibility(model: model).acceptsSteering(operation))
		model.composer.uncertainSubmissions.insert(UUID())
		#expect(WorkspaceEligibility(model: model).canSteer)
		#expect(WorkspaceEligibility(model: model).acceptsSteering(operation))
		model.execution.activeTurnID = "new turn"
		#expect(!WorkspaceEligibility(model: model).acceptsSteering(operation))
		model.execution.activeTurnID = nil
		#expect(!WorkspaceEligibility(model: model).canSteer)
	}

	@Test func acceptedSubmissionDoesNotRevalidateNextTurnPreferenceChanges()
	{
		var model = fixture()
		let captured = proposal(model)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionRequested(captured))
		)
		_ = ComposerReducer.reduce(
			&model,
			.execution(.submissionRequested(captured))
		)
		model.preferences.runPreferences = RunPreferences(
			approvalMode: .fullAccess,
			fastMode: true
		)
		#expect(model.composer.pendingSubmissions[captured.context.requestID]?
			.preferences == .standard)
		#expect(!WorkspaceEligibility(model: model).canSend)
	}

	@Test func warningsKeepCatalogueAheadOfHydrationAndModelSelection()
	{
		var model = fixture()
		model.preferences.selectedModelID = "unavailable"
		model.contextNavigation.pendingContextLoad = ContextLoadOperation(
			context: proposal(model).context,
			revision: 0
		)
		model.preferences.modelListError = "Catalogue failed."
		#expect(WorkspaceEligibility(model: model).preferenceWarning ==
			"Catalogue failed. Reconnect before sending.")
		model.preferences.modelListError = nil
		#expect(WorkspaceEligibility(model: model)
			.preferenceWarning == "Project context is loading.")
		model.contextNavigation.pendingContextLoad = nil
		#expect(WorkspaceEligibility(model: model).preferenceWarning != nil)
	}

	@Test func cleanupLeaseAndStaleManagementScopeBlockEveryCommandCapability()
	{
		var model = fixture()
		model.conversations.selectedConversation = .thread("selected")
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "selected"
		)
		#expect(WorkspaceEligibility(model: model).acceptsManagement(.archive(context)))
		model.conversations.selectedConversation = .thread("other")
		#expect(!WorkspaceEligibility(model: model).acceptsManagement(.archive(context)))
		model.conversations.selectedConversation = .thread("selected")
		model.lifecycle.cleanupReservation = WorkspaceCleanupRequest(
			requestID: UUID(),
			owner: WorkspaceLifecycleReducer.reference(model),
			expected: TaskWorkspace(
				id: UUID(),
				taskID: "task",
				sourceProjectPath: "/source",
				repositoryGitDirectory: "/source/.git",
				branch: "codex/task",
				checkoutPath: "/project",
				baseCommit: "base",
				sourceWasDirty: false,
				createdAt: .distantPast,
				phase: .active
			)
		)
		#expect(!WorkspaceEligibility(model: model).canSend)
		#expect(!WorkspaceEligibility(model: model).canManageThreads)
		model.execution.state = .running
		model.execution.activeThreadID = "selected"
		model.execution.activeTurnID = "turn"
		#expect(!WorkspaceEligibility(model: model).canSteer)
	}

	@Test func unresolvedComposerOwnershipBlocksStaleManagementAfterExecutionReset()
	{
		var model = fixture()
		let unresolved = proposal(model)
		model.composer.pendingSubmissions[unresolved.context.requestID] = unresolved
		model.composer.uncertainSubmissions.insert(unresolved.context.requestID)
		// New Chat reset can clear execution ownership independently of the retained submission.
		model.execution.owner = nil
		model.conversations.selectedConversation = .thread("selected")
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "selected"
		)
		#expect(!WorkspaceSelectors(
			model: model,
			now: .distantPast
		).makeSnapshot()
			.canManageThreads)
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.managementRequested(.archive(context)))
		)
		#expect(result.effects.isEmpty)
		#expect(model.conversations.pendingManagement == nil)
		model.composer.uncertainSubmissions.removeAll()
		model.execution.hasUncertainRequest = true
		#expect(!WorkspaceEligibility(model: model).canManageThreads)
	}

	@Test func attachedInputMustMatchCapturedDescriptionsImagesAndInputCount()
	{
		var model = fixture()
		let image = ComposerContextItem(
			kind: .image,
			title: "Capture",
			path: "/project/image.png"
		)
		model.composer.drafts[.newChat]?.context = [image]
		let captured = proposal(model)
		func withInputs(_ inputs: [TurnInput]) -> ComposerSubmission
		{
			ComposerSubmission(
				context: captured.context,
				conversation: captured.conversation,
				draft: captured.draft,
				inputs: inputs,
				skills: captured.skills,
				modelID: captured.modelID,
				effort: captured.effort,
				preferences: captured.preferences,
				retainedContextRequestID: captured.retainedContextRequestID,
				projectContextRevision: 0
			)
		}
		let text = "request\n\n" + UserMessageContextDescription.image(title: "Capture")
		#expect(WorkspaceEligibility(model: model).acceptsSubmission(withInputs([
			.text(text),
			.localImage(path: "/project/image.png")
		])))
		for inputs: [TurnInput] in [
			[.text("request\n\nArbitrary instruction"), .localImage(path: "/project/image.png")],
			[.text(text), .localImage(path: "/project/other.png")],
			[
				.text(text),
				.localImage(path: "/project/image.png"),
				.localImage(path: "/project/extra.png")
			]
		]
		{
			#expect(!WorkspaceEligibility(model: model).acceptsSubmission(withInputs(inputs)))
		}
	}

	@Test func preparedExcerptPreservesLineBoundsAndBlankLines() throws
	{
		let cases: [(first: Int?, last: Int?, expected: String)] = [
			(nil, nil, "Selected code from Example.swift, lines 1–1:\n1: \n2: value\n3: "),
			(4, nil, "Selected code from Example.swift, lines 4–4:\n4: \n5: value\n6: "),
			(nil, 3, "Selected code from Example.swift, lines 1–3:\n1: \n2: value\n3: "),
			(4, 6, "Selected code from Example.swift, lines 4–6:\n4: \n5: value\n6: ")
		]
		for value in cases
		{
			var model = fixture()
			let item = ComposerContextItem(
				kind: .textExcerpt,
				title: "Example.swift",
				path: "Example.swift",
				firstLine: value.first,
				lastLine: value.last,
				excerpt: "\nvalue\n"
			)
			model.composer.drafts[.newChat]?.context = [item]
			let captured = proposal(model)
			let inputs = try ComposerContextBuilder.inputs(
				text: captured.draft.text,
				items: captured.draft.context,
				project: URL(fileURLWithPath: "/project")
			)
			#expect(inputs == [.text("request\n\n" + value.expected)])
			let prepared = ComposerSubmission(
				context: captured.context,
				conversation: captured.conversation,
				draft: captured.draft,
				inputs: inputs,
				skills: captured.skills,
				modelID: captured.modelID,
				effort: captured.effort,
				preferences: captured.preferences,
				retainedContextRequestID: captured.retainedContextRequestID,
				projectContextRevision: 0
			)
			#expect(WorkspaceEligibility(model: model).acceptsSubmission(prepared))
		}
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/project"
		))
		model.connection.generation = 1
		model.connection.isConnected = true
		model.execution.state = .ready
		model.composer.drafts[.newChat] = ComposerDraft(
			text: "request",
			revision: 1
		)
		return model
	}

	private func proposal(_ model: WorkspaceModel) -> ComposerSubmission
	{
		let draft = model.composer.drafts[.newChat] ?? ComposerDraft()
		return ComposerSubmission(
			context: OperationContext(
				workspace: model.identity,
				generation: model.connection.generation,
				requestID: UUID()
			),
			conversation: .newChat,
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID(),
			projectContextRevision: 0
		)
	}
}
