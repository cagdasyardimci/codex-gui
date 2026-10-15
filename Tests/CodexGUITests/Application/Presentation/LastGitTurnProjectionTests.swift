import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct LastGitTurnProjectionTests
{
	@Test func latestActualTurnIncludesTurnsWithoutReportedChanges()
	{
		let snapshot = WorkspaceSelectors(
			model: model(turns: [turn("older"), turn("latest")]),
			now: .distantPast
		).makeSnapshot()
		#expect(snapshot.lastGitTurnID == "latest")
		#expect(snapshot.reviewTurns.isEmpty)
		#expect(ReviewPresentation(snapshot).key.lastGitTurnID == "latest")
	}

	@Test func activeTurnBeforeHistoryPublicationTakesPrecedence()
	{
		var value = model(turns: [turn("older")])
		value.execution.activeThreadID = "viewed"
		value.execution.activeTurnID = "live"
		value.execution.state = .running
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "live")
	}

	@Test func completedOrOlderActiveIdentityDoesNotOverrideNewerHistory()
	{
		var value = model(turns: [turn("older"), turn("newer")])
		value.execution.activeThreadID = "viewed"
		value.execution.activeTurnID = "older"
		value.execution.state = .ready
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "newer")
		value.execution.state = .running
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "newer")
	}

	@Test func anotherChatActiveTurnAndBindingRevisionStayWithTheirOwner()
	{
		var value = model(turns: [turn("viewed-latest")])
		value.execution.activeThreadID = "other"
		value.execution.activeTurnID = "other-live"
		value.execution.state = .running
		value.execution.gitTurnBaselineRevisions = ["viewed": 2, "other": 8]
		let snapshot = WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
		#expect(snapshot.lastGitTurnID == "viewed-latest")
		#expect(snapshot.gitTurnBaselineRevision == 2)
		let original = ReviewPresentation(snapshot)
		value.execution.gitTurnBaselineRevisions["viewed"] = 3
		let updated = ReviewPresentation(WorkspaceSelectors(
			model: value,
			now: .distantPast
		)
		.makeSnapshot())
		#expect(original != updated)
		value.conversations.selectedConversation = .newChat
		let newChat = WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
		#expect(newChat.lastGitTurnID == nil)
		#expect(newChat.gitTurnBaselineRevision == 0)
	}

	@Test func externalStartedTurnOverridesCompletedLocalOwnerAndSurvivesLateOldCompletion()
	{
		var value = model(turns: [turn("old-local")])
		value.execution.activeThreadID = "viewed"
		value.execution.activeTurnID = "old-local"
		value.execution.state = .ready
		let started = CodexTurn(
			id: "external-new",
			status: "inProgress",
			items: [],
			error: nil
		)
		ConversationContentReducer.observe(
			.turnStarted(
				threadId: "viewed",
				turn: started
			),
			model: &value
		)
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "viewed",
				turn: turn("old-local")
			),
			model: &value
		)
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
		value.execution.state = .running
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
		value.conversations.content[.thread("viewed")]?.loadedTurns.insert(
			turn("earlier-page"),
			at: 0
		)
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
	}

	@Test func olderHistoryReadCannotRollBackExternallyStartedTurn()
	{
		var value = model(turns: [turn("old-local")])
		value.execution.activeThreadID = "viewed"
		value.execution.activeTurnID = "old-local"
		value.execution.state = .ready
		let started = CodexTurn(
			id: "external-new",
			status: "inProgress",
			items: [],
			error: nil
		)
		ConversationContentReducer.observe(
			.turnStarted(
				threadId: "viewed",
				turn: started
			),
			model: &value
		)
		let summary = ThreadSummary(json: ["id": "viewed", "cwd": "/tmp/neutral-turn-projection"])!
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [turn("old-local")],
				nextTurnsCursor: nil
			),
			model: &value
		)
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [turn("old-local"), turn("external-new")],
				nextTurnsCursor: nil
			),
			model: &value
		)
		#expect(WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
			.lastGitTurnID == "external-new")
	}

	private func model(turns: [CodexTurn]) -> WorkspaceModel
	{
		var value = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/neutral-turn-projection"
		))
		value.conversations.selectedConversation = .thread("viewed")
		value.conversations
			.content[.thread("viewed")] = ConversationContentModel(loadedTurns: turns)
		return value
	}

	private func turn(_ id: String) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: "completed",
			items: [],
			error: nil
		)
	}
}
