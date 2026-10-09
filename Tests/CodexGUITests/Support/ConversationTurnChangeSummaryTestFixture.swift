import Foundation

@testable import CodexGUI

@MainActor
enum ConversationTurnChangeSummaryTestFixture
{
	static func makeSnapshot(
		selectedThreadID: String = "thread",
		executionState: ExecutionState = .running,
		activeTurnDiff: String? = nil,
		reports: Bool = true
	) -> ConversationSnapshot
	{
		let edit = FileChange(json: [
			"path": "Sources/First.swift",
			"kind": "update",
			"diff": "@@ -1 +1,2 @@\n-old\n+new\n+extra",
		])!
		let secondEdit = FileChange(json: [
			"path": "Sources/First.swift",
			"kind": "update",
			"diff": "@@ -3 +3,2 @@\n line\n+again",
		])!
		let addition = FileChange(json: [
			"path": "Sources/Second.swift",
			"kind": "add",
			"diff": "",
		])!
		let entry = ConversationEntry(
			id: "turn:item",
			kind: .tool,
			title: "File changes",
			body: "",
			activity: .fileChanges(
				[edit, secondEdit, addition],
				status: "completed"
			)
		)
		let previous = ConversationEntry(
			id: "previous:item",
			kind: .tool,
			title: "Old changes",
			body: "",
			activity: .fileChanges(
				[edit],
				status: "completed"
			)
		)
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/replay",
			threads: [],
			selectedThreadID: selectedThreadID,
			entries: reports ? [previous, entry] : [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: true,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: executionState,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.activeThreadID = "thread"
		snapshot.activeTurnID = "turn"
		snapshot.activeTurnDiff = activeTurnDiff
		snapshot.reportedGitTurnID = reports ? "turn" : nil
		snapshot.reportedGitChanges = reports ? [edit, secondEdit, addition] : nil
		return snapshot
	}
}
