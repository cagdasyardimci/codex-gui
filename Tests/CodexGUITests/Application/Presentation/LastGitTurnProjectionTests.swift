import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct LastGitTurnProjectionTests
{

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
