import AppKit
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct LatestAgentResponseTests
{

	@Test func copyUsesLatestAgentBodyInSelectedSnapshotOnly()
	{
		let entries = [
			ConversationEntry(
				id: "a",
				kind: .agent,
				title: "Codex",
				body: "First reply"
			),
			ConversationEntry(
				id: "b",
				kind: .user,
				title: "You",
				body: "User message"
			),
			ConversationEntry(
				id: "c",
				kind: .agent,
				title: "Codex",
				body: "Latest reply 🧭"
			),
			ConversationEntry(
				id: "d",
				kind: .command,
				title: "Command",
				body: "Tool output"
			),
		]
		#expect(MainWindowController.latestAgentResponse(in: snapshot(entries)) == "Latest reply 🧭")
		#expect(MainWindowController.latestAgentResponse(in: snapshot([])) == nil)
		#expect(MainWindowController
			.latestAgentResponse(in: snapshot([entries[1], entries[3]])) == nil)
	}

	private func snapshot(_ entries: [ConversationEntry]) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: nil,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Test",
			backendDescription: "Test",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
	}
}
