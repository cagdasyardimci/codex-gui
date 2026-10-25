import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
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

	private struct TestFailure: Error
	{
	}
}
