import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConcurrentComposerCommandTests
{
	@Test func backgroundSettingsFailureBlocksOnlyItsConversation() throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/concurrent-commands"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("displayed")
		let draft = ComposerDraft(text: "/plan")
		let invocation: SlashCommandInvocation
		guard case .command(let command) = SlashCommandParser.parse(draft.text)
		else
		{
			throw TestFailure()
		}
		invocation = command
		let request = SlashCommandPresentationRequest(
			context: OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID(),
				threadID: "background"
			),
			invocation: invocation,
			conversation: .thread("background"),
			draft: draft
		)
		let operation = ComposerCommandSettingsOperation(
			request: request,
			mode: CollaborationMode(
				mode: .plan,
				model: "model",
				reasoningEffort: nil
			)
		)
		model.composerCommands.pendingSettings = operation
		model.composer.drafts[.thread("background")] = draft
		model.composer.drafts[.thread("displayed")] = ComposerDraft(text: "independent draft")
		_ = ComposerCommandReducer.reduce(
			&model,
			.composerCommand(.settingsFinished(
				operation,
				.failed(OperationFailure(
					message: "transport lost",
					outcomeIsUncertain: true
				))
			))
		)
		#expect(model.composerCommands.error == nil)
		#expect(model.composerCommands.conversationErrors[.thread("background")] != nil)
		#expect(model.composerCommands.conversationErrors[.thread("displayed")] == nil)
		#expect(model.execution(for: .thread("background")).needsReconciliation)
		#expect(!model.execution.needsReconciliation)
		#expect(model.composerCommands.blocksNewWork(for: .thread("background")))
		#expect(!model.composerCommands.blocksNewWork(for: .thread("displayed")))
		#expect(model.composer.drafts[.thread("displayed")]?.text == "independent draft")
	}

	@Test func backgroundSteeringAcknowledgementConsumesOnlyCapturedOwnerDraft()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/concurrent-steering"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("displayed")
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: "background",
			turnID: "running-turn"
		)
		let draft = ComposerDraft(
			text: "steer the running turn",
			revision: 2
		)
		let submission = ComposerSubmission(
			context: context,
			conversation: .thread("background"),
			draft: draft,
			inputs: [.text(draft.text)],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let operation = SteeringOperation(
			context: context,
			submission: submission
		)
		var running = ExecutionModel()
		running.state = .running
		running.activeThreadID = "background"
		running.activeTurnID = "running-turn"
		running.pendingSteering = context
		model.executions.entries[.thread("background")] = running
		model.composer.drafts[.thread("background")] = draft
		model.composer.drafts[.thread("displayed")] = draft
		_ = ComposerReducer.reduce(
			&model,
			.execution(.steeringRequested(operation))
		)
		#expect(model.composer.pendingSubmissions[context.requestID]?.conversation
			== .thread("background"))
		let result = ComposerReducer.reduce(
			&model,
			.execution(.steeringFinished(
				context,
				.succeeded("running-turn")
			))
		)
		#expect(model.composer.drafts[.thread("background")]?.text == "")
		#expect(model.composer.drafts[.thread("displayed")] == draft)
		#expect(model.execution(for: .thread("background")).activeTurnID == "running-turn")
		#expect(model.conversations.selectedConversation == .thread("displayed"))
		#expect(result.effects.count == 1)
		#expect(result.effects.contains
		{
			if case .acknowledgeSubmission(let write) = $0
			{
				return write.threadID == "background"
			}
			return false
		})
	}

	private struct TestFailure: Error
	{
	}
}
