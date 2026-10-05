import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConcurrentConversationOwnershipTests
{
	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/concurrent-conversations"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		return model
	}

	private func context(
		_ model: WorkspaceModel,
		threadID: String? = nil
	) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID(),
			threadID: threadID
		)
	}

	@Test func selectionLeavesAnonymousPreparationAndIndependentDraftsOwned()
	{
		var model = fixture()
		let preparation = context(model)
		model.execution.owner = ExecutionOwner(submission: preparation)
		model.execution.state = .running
		model.composer.drafts[.newChat] = ComposerDraft(text: "anonymous input")
		model.composer.drafts[.thread("other")] = ComposerDraft(text: "other input")
		let selection = context(
			model,
			threadID: "other"
		)
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.selectionRequested(selection))
		)
		#expect(model.conversations.selectedConversation == .thread("other"))
		#expect(model.execution(for: preparation)?.state == .running)
		#expect(model.execution(for: preparation)?.owner?.submission == preparation)
		#expect(model.execution.state == .ready)
		#expect(model.composer.drafts[.newChat]?.text == "anonymous input")
		#expect(model.composer.drafts[.thread("other")]?.text == "other input")
		#expect(result.effects.contains
		{
			if case .readConversationHistory = $0
			{
				return true
			}
			return false
		})
	}

	@Test func backgroundHistoryUsesItsExecutionRevision()
	{
		var model = fixture()
		model.conversations.selectedConversation = .thread("displayed")
		model.execution.commandEventRevisions["background"] = 19
		var background = ExecutionModel()
		background.commandEventRevisions["background"] = 4
		model.executions.entries[.thread("background")] = background
		let operation = ConversationReadOperation(
			context: context(
				model,
				threadID: "background"
			),
			commandRevision: 4,
			purpose: .search
		)
		let result = ConversationReducer.reduce(
			&model,
			.conversations(.historyRequested(operation))
		)
		#expect(model.conversations.pendingReads[operation.key]?.commandRevision == 4)
		#expect(result.effects.count == 1)
		#expect(model.execution.commandEventRevisions["background"] == 19)
	}

	@Test func backgroundRecoveryFailureRetainsItsErrorWithoutChangingDisplayedChat()
	{
		var model = fixture()
		model.conversations.selectedConversation = .thread("displayed")
		let operation = ConversationReadOperation(
			context: context(
				model,
				threadID: "background"
			),
			commandRevision: 0,
			purpose: .recovery
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.historyRequested(operation))
		)
		let pending = model.conversations.pendingReads[operation.key]!
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.historyReceived(
				pending,
				.failed(OperationFailure(
					message: "background unavailable",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.conversations.historyErrors["background"]?
			.contains("background unavailable") == true)
		#expect(model.conversations.error == nil)
		#expect(model.execution(for: .thread("background")).needsReconciliation)
		#expect(!model.execution.needsReconciliation)
		#expect(model.conversations.selectedConversation == .thread("displayed"))
	}

	@Test func repeatedNewChatDetachesOldTranscriptBeforeLatePreparation()
	{
		var model = fixture()
		let submitted = context(model)
		let draft = ComposerDraft(
			text: "old input",
			lifetime: 2
		)
		let submission = ComposerSubmission(
			context: submitted,
			conversation: .newChat,
			draft: draft,
			inputs: [],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		model.composer.drafts[.newChat] = draft
		model.execution.owner = ExecutionOwner(submission: submitted)
		model.execution.state = .running
		model.composer.pendingSubmissions[submitted.requestID] = submission
		model.composer.submissionConversations[submitted.requestID] = .newChat
		let oldEntry = ConversationEntry(
			id: "local:\(submitted.requestID)",
			kind: .user,
			title: "You",
			body: "old input"
		)
		model.conversations.content[.newChat] = ConversationContentModel(entries: [oldEntry])
		_ = ComposerReducer.reduce(
			&model,
			.conversations(.newChatOpened(context(model)))
		)
		#expect(model.conversations.content[.newChat]?.entries.isEmpty == true)
		#expect(model.conversations.pendingNewChatContent[2]?.entries == [oldEntry])
		let independent = model.composer.drafts[.newChat]
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: ThreadSummary(json: [
					"id": "prepared",
					"cwd": "/tmp/concurrent-conversations",
				])!,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		_ = ExecutionReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submitted,
				.succeeded(prepared)
			))
		)
		let preparation = ComposerReducer.reduce(
			&model,
			.execution(.submissionPrepared(
				submitted,
				.succeeded(prepared)
			))
		)
		for event in preparation.domainEvents
		{
			_ = ConversationReducer.reduceDomainEvent(
				&model,
				event
			)
		}
		#expect(model.conversations.selectedConversation == .newChat)
		#expect(model.composer.drafts[.newChat] == independent)
		#expect(model.conversations.content[.thread("prepared")]?.entries == [oldEntry])
		#expect(model.conversations.content[.newChat]?.entries.isEmpty == true)
		#expect(model.conversations.pendingNewChatContent[2] == nil)
	}
}
