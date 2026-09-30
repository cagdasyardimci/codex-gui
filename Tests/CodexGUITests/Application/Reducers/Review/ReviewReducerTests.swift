import Foundation
import Testing
@testable import CodexGUI

@MainActor
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

	@Test func historicalSelectionSurvivesLaterReportedChangesWhileLatestFollows()
	{
		var model = fixture()
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				context(model),
				conversation: .thread("thread"),
				turnID: "first"
			))
		)
		model.conversations.content[.thread("thread")]?.loadedTurns.append(turn("next"))
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		#expect(model.review.conversations[.thread("thread")]?.selectedTurnID == "first")
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				context(model),
				conversation: .thread("thread"),
				turnID: "next"
			))
		)
		model.conversations.content[.thread("thread")]?.loadedTurns.append(turn("final"))
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		#expect(model.review.conversations[.thread("thread")]?.selectedTurnID == "final")
	}

	@Test func unchangedFingerprintRefreshStillReplacesObsoletePendingRead()
	{
		var model = fixture()
		let first = read(model)
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		let result = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let next = read(model)
		#expect(result.effects.count == 1)
		#expect(next.identities == first.identities)
		#expect(next.sourceRevision > first.sourceRevision)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				first,
				.succeeded(first.identities)
			))
		)
		#expect(model.review.conversations[.thread("thread")]?.pendingMarkerLoad == next)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				next,
				.succeeded(next.identities)
			))
		)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		)
			== Set(next.identities.map(\.reference)))
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

	@Test func olderMarkerReadCannotUndoNewerMarkerEdit()
	{
		var model = fixture()
		let operation = read(model)
		let marked = identity(model)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markerRequested(
				context(model),
				identity: marked,
				reviewed: true
			))
		)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				operation,
				.succeeded([])
			))
		)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		) == [marked.reference])
	}

	@Test func supersededWriteFailureCannotRetireNewerWriteOrSurfaceError()
	{
		var model = fixture()
		let marked = identity(model)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markerRequested(
				context(model),
				identity: marked,
				reviewed: true
			))
		)
		let first = model.review.conversations[.thread("thread")]!
			.pendingMarkerWrites[marked.reference]!
		_ = ReviewReducer.reduce(
			&model,
			.review(.markerRequested(
				context(model),
				identity: marked,
				reviewed: false
			))
		)
		let second = model.review.conversations[.thread("thread")]!
			.pendingMarkerWrites[marked.reference]!
		_ = ReviewReducer.reduce(
			&model,
			.review(.markerPersistenceFinished(
				first,
				.failed(OperationFailure(
					message: "old failure",
					outcomeIsUncertain: false
				))
			))
		)
		#expect(model.review.conversations[.thread("thread")]?
			.pendingMarkerWrites[marked.reference] == second)
		#expect(model.review.conversations[.thread("thread")]?.error == nil)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		).isEmpty)
	}

	@Test func staleSourceReadAndForeignIdentitiesCannotMarkCurrentChanges()
	{
		var model = fixture()
		let old = read(model)
		let marked = identity(model)
		model.conversations.content[.thread("thread")]?.loadedTurns[1] = turn(
			"latest",
			addition: "different"
		)
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let current = read(model)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				old,
				.succeeded([marked])
			))
		)
		#expect(model.review.conversations[.thread("thread")]?.pendingMarkerLoad == current)
		_ = ReviewReducer.reduce(
			&model,
			.review(.markersReceived(
				current,
				.succeeded([marked])
			))
		)
		#expect(ReviewReducer.reviewedReferences(
			model,
			.thread("thread")
		).isEmpty)
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

	@Test func validRevisionPrependsExactSourceToDraftWithoutSteering() throws
	{
		var model = fixture()
		model.composer.drafts[.thread("thread")] = ComposerDraft(
			text: "Keep existing draft",
			revision: 4
		)
		let turn = try #require(ReviewReducer.selectedTurn(
			model,
			.thread("thread")
		))
		let file = try #require(turn.files.first)
		let hunk = try #require(file.hunks.first)
		let reference = ReviewReference(
			threadID: "thread",
			turnID: turn.turnID,
			file: file,
			hunk: hunk
		)
		let request = ChangeRequest(
			reference: reference,
			file: file,
			hunk: hunk,
			kind: .revision,
			sourceRevision: 1
		)
		let result = ComposerReducer.reduce(
			&model,
			.review(.changeRequestPrepared(
				context(model),
				request
			))
		)
		let draft = try #require(model.composer.drafts[.thread("thread")])
		#expect(draft.text == reference.prompt(
			for: .revision,
			file: file,
			hunk: hunk
		)
			+ "Keep existing draft")
		#expect(draft.revision == 5)
		#expect(result.effects.count == 1)
		guard case .persistDraft = result.effects[0]
		else
		{
			Issue.record("Revision preparation must only persist its composed draft.")
			return
		}
		model.conversations.content[.thread("thread")]?.reviewSourceRevision += 1
		_ = ReviewReducer.reduceDomainEvent(
			&model,
			.conversationContentChanged
		)
		let stale = ComposerReducer.reduce(
			&model,
			.review(.changeRequestPrepared(
				context(model),
				request
			))
		)
		#expect(stale.effects.isEmpty)
		#expect(model.composer.drafts[.thread("thread")]?.revision == 5)
		_ = ReviewReducer.reduce(
			&model,
			.review(.turnSelected(
				context(model),
				conversation: .thread("thread"),
				turnID: "first"
			))
		)
		#expect(!ReviewReducer.accepts(
			context(model),
			request,
			model: model
		))
	}
}
