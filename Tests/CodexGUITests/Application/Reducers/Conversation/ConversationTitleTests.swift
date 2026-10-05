import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConversationTitleTests
{
	@Test func provisionalTitleUsesNormalizedPromptAndPreservesUnicode()
	{
		#expect(ThreadTitleText
			.placeholder("  Fix\n\tbaşlık   updates  ") == "Fix başlık updates")
		#expect(ThreadTitleText.placeholder(" \n ") == "New chat")
		#expect(ThreadTitleText.placeholder(String(
			repeating: "👩🏽‍💻",
			count: 130
		)).count == 120)
	}

	@Test func newSubmissionGetsTitleBeforeAnyAgentResponse()
	{
		var model = workspace()
		model.conversations.selectedConversation = .newChat
		let submission = ComposerSubmission(
			context: context(model),
			conversation: .newChat,
			draft: ComposerDraft(text: "wait for 30 seconds and create a placeholder"),
			inputs: [.text("wait for 30 seconds and create a placeholder")],
			skills: [],
			modelID: nil,
			effort: nil,
			preferences: .standard,
			retainedContextRequestID: UUID()
		)
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/titles"])!,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.submissionPrepared(prepared)
		)
		#expect(model.conversations.threads.first?.preview == submission.draft.text)
		#expect(model.conversations.threads.first?.name == nil)
	}

	@Test func notificationUpdatesUnselectedChatAndSurvivesOlderListResponse()
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		let operation = ConversationListOperation(
			context: context(model),
			archived: false,
			boundThreadID: nil
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(operation))
		)
		observeTitle(
			"Create placeholder",
			model: &model
		)
		#expect(model.conversations.threads.first?.name == "Create placeholder")
		#expect(model.conversations.selectedConversation == .newChat)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				operation,
				.succeeded([summary()])
			))
		)
		#expect(model.conversations.threads.first?.name == "Create placeholder")
		observeTitle(
			nil,
			model: &model
		)
		#expect(model.conversations.threads.first?.name == nil)
	}

	@Test func aFreshListCanReplacePreviouslyObservedTitleMetadata()
	{
		var model = workspace()
		model.conversations.threads = [summary()]
		observeTitle(
			"Generated title",
			model: &model
		)
		let operation = ConversationListOperation(
			context: context(model),
			archived: false,
			boundThreadID: nil
		)
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListRequested(operation))
		)
		var renamed = summary()
		renamed.name = "My chosen name"
		_ = ConversationReducer.reduce(
			&model,
			.conversations(.threadListReceived(
				operation,
				.succeeded([renamed])
			))
		)
		#expect(model.conversations.threads.first?.name == "My chosen name")
	}

	@Test func protocolTitleParsingRejectsMalformedOrEmptyOutput()
	{
		#expect(AutomaticTitleResponse.title("{\"title\":\" Create   placeholder \"}")
			== "Create placeholder")
		#expect(AutomaticTitleResponse.title("{\"title\":\"  \"}") == nil)
		#expect(AutomaticTitleResponse.title("Do something else") == nil)
		#expect(AutomaticTitleResponse.title("{\"title\":12}") == nil)
	}

	private func observeTitle(
		_ name: String?,
		model: inout WorkspaceModel
	)
	{
		_ = ConversationReducer.reduceDomainEvent(
			&model,
			.backendObserved(
				.threadNameUpdated(
					threadId: "thread",
					name: name
				),
				observedAt: nil
			)
		)
	}

	private func workspace() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/titles"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		model.execution.state = .ready
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: 1,
			requestID: UUID()
		)
	}

	private func summary() -> ThreadSummary
	{
		ThreadSummary(json: ["id": "thread", "cwd": "/tmp/titles", "preview": "Original prompt"])!
	}
}
