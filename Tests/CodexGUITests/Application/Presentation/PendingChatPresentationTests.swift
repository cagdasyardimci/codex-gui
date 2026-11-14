import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct PendingChatPresentationTests
{
	@Test(arguments: [true, false])
	func acceptedFirstMessageAppearsBeforeCreationAndSettlesWithoutDuplicateRows(
		succeeds: Bool
	) throws
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/new-chat"
		))
		model.connection.isConnected = true
		model.connection.generation = 1
		let draft = ComposerDraft(
			text: "Create a useful feature",
			lifetime: 2
		)
		model.composer.drafts[.newChat] = draft
		let context = OperationContext(
			workspace: model.identity,
			generation: 1,
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
			retainedContextRequestID: UUID()
		)
		apply(
			&model,
			.execution(.submissionRequested(submission))
		)
		let pending = WorkspaceSelectors(
			model: model,
			now: .distantPast
		).makeSnapshot()
		let chat = try #require(pending.pendingChats.first)
		#expect(pending.threads.isEmpty)
		#expect(pending.pendingChats.count == 1)
		#expect(chat.requestID == context.requestID)
		#expect(chat.title == draft.text)
		#expect(chat.projectPath == "/tmp/new-chat")
		#expect(chat.isSelected)

		// Opening another draft must retain this row under its captured project.
		apply(
			&model,
			.conversations(.newChatOpened(OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID()
			)))
		)
		let background = WorkspaceSelectors(
			model: model,
			now: .distantPast
		).makeSnapshot()
		#expect(background.pendingChats.map(\.requestID) == [context.requestID])
		#expect(background.pendingChats.first?.isSelected == false)
		let independentDraft = model.composer.drafts[.newChat]

		let oldList = ConversationListOperation(
			context: OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID()
			),
			archived: false,
			boundThreadID: nil
		)
		model.conversations.pendingList = oldList
		let thread = try #require(ThreadSummary(json: ["id": "created", "cwd": "/tmp/new-chat"]))
		let prepared = PreparedSubmission(
			submission: submission,
			thread: ThreadDetail(
				summary: thread,
				turns: [],
				nextTurnsCursor: nil
			)
		)
		apply(
			&model,
			.execution(.submissionPrepared(
				context,
				succeeds ? .succeeded(prepared) : .failed(OperationFailure(
					message: "Rejected",
					outcomeIsUncertain: false
				))
			))
		)
		apply(
			&model,
			.conversations(.threadListReceived(
				oldList,
				.succeeded([])
			))
		)
		let finished = WorkspaceSelectors(
			model: model,
			now: .distantPast
		).makeSnapshot()
		#expect(finished.pendingChats.isEmpty)
		#expect(finished.threads.map(\.id) == (succeeds ? ["created"] : []))
		#expect(finished.selectedThreadID == nil)
		#expect(model.composer.drafts[.newChat] == independentDraft)
	}

	private func apply(
		_ model: inout WorkspaceModel,
		_ action: WorkspaceAction
	)
	{
		var events = WorkspaceFeatureComposition.reduce(
			&model,
			action
		).domainEvents
		while !events.isEmpty
		{
			let event = events.removeFirst()
			events
				.append(contentsOf: WorkspaceDomainComposition.reduceDomainEvent(
					&model,
					event
				)
				.domainEvents)
		}
	}
}
