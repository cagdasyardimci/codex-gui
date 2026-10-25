import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct ReviewReducerTests
{
	private func turn(
		_ id: String,
		addition: String = "new"
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [CodexItem(json: [
				"id": "change-\(id)",
				"type": "fileChange",
				"status": "completed",
				"changes": [["path": "Sources/A.swift",
								"kind": "update",
								"diff": "@@ -1 +1 @@\n-old\n+\(addition)\n"]]
			])!],
			error: nil
		)
	}

	private func fixture() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/review"
		))
		model.connection.generation = 1
		model.conversations.selectedConversation = .thread("thread")
		model.conversations.content[.thread("thread")] = ConversationContentModel(
			loadedTurns: [turn("first"), turn("latest")],
			reviewSourceRevision: 1
		)
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				context(model),
				conversation: .thread("thread"),
				turnID: "latest"
			))
		)
		return model
	}

	private func context(_ model: WorkspaceModel) -> OperationContext
	{
		OperationContext(
			workspace: model.identity,
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
	}

	private func identity(_ model: WorkspaceModel) -> ReviewMarkerIdentity
	{
		ReviewReducer.identities(ReviewReducer.selectedTurn(
			model,
			.thread("thread")
		)!)[0]
	}

	private func read(_ model: WorkspaceModel) -> ReviewMarkerReadOperation
	{
		model.review.conversations[.thread("thread")]!.pendingMarkerLoad!
	}

	@Test func changedSourceReadRetiresOnlyItsMatchingTicketWithoutCachingOldMarkers()
	{
		var model = fixture()
		let operation = read(model)
		model.conversations.selectedConversation = .newChat
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				operation,
				.succeeded(operation
					.identities)
			))
		)
		#expect(model.review.conversations[.thread("thread")]?.pendingMarkerLoad == nil)
		#expect(model.review.conversations[.thread("thread")]?.loadedMarkerSnapshot == nil)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		).isEmpty)
		#expect(model.conversations.selectedConversation == .newChat)
		model.conversations.selectedConversation = .thread("thread")
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				context(model),
				conversation: .thread("thread"),
				turnID: "latest"
			))
		)
		#expect(read(model).sourceRevision > operation.sourceRevision)
	}

	@Test func oldGenerationAndDifferentCheckoutCannotChangeSelectionOrMarkers()
	{
		var model = fixture()
		let old = read(model)
		model.connection.generation += 1
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				old,
				.succeeded(old.identities)
			))
		)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		).isEmpty)
		let foreign = OperationContext(
			workspace: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/tmp/other"
			),
			generation: model.connection.generation,
			requestID: UUID(),
			threadID: "thread"
		)
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				foreign,
				conversation: .thread("thread"),
				turnID: "first"
			))
		)
		#expect(model.review.conversations[.thread("thread")]?.selectedTurnID == "latest")
	}

}
