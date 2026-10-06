import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptNetFileChangeSummaryTests
{
	@Test func interleavedFileActivitiesKeepTheirPreparedSummaryWhenWorkIsFolded() async
	{
		let first = ConversationEntry(
			id: "turn:first-edit",
			kind: .tool,
			title: "Changed file",
			body: "",
			activity: .fileChanges(
				[change(diff: "@@ -1 +1 @@\n-before\n+intermediate")],
				status: "completed"
			)
		)
		let second = ConversationEntry(
			id: "turn:second-edit",
			kind: .tool,
			title: "Changed file",
			body: "",
			activity: .fileChanges(
				[change(diff: "@@ -1 +1 @@\n-intermediate\n+after")],
				status: "completed"
			)
		)
		let entries = [
			first,
			ConversationEntry(
				id: "turn:comment",
				kind: .agent,
				title: "Codex",
				body: "Working"
			),
			second,
			ConversationEntry(
				id: "turn:reply",
				kind: .agent,
				title: "Codex",
				body: "Done"
			),
			ConversationEntry(
				id: "next:request",
				kind: .user,
				title: "You",
				body: "Next"
			)
		]
		let sources = TranscriptPreparationCoordinator.fileChangeSources(from: entries)
		#expect(sources.count == 1)
		#expect(sources.first?.changes.count == 2)
		let cache = ConversationNetFileChangePreparation()
		let prepared = await cache.prepare(
			sources,
			context: "thread"
		)
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: nil,
			preparedNetChanges: prepared ?? [:]
		)
		let timings = [ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			startedAt: Date(timeIntervalSince1970: 1_000)
		)]
		let collapsed = ConversationTranscriptRow.collapsingWork(
			in: rows,
			workEntryIDs: ConversationTranscriptRow.workEntryIDs(
				entries: entries,
				timings: timings
			),
			expandedTurnIDs: []
		)
		let summaries = collapsed.compactMap
		{
			row -> ConversationEntry? in
			guard case .message(let entry) = row, entry.activity.isFileChange
			else
			{
				return nil
			}
			return entry
		}
		#expect(summaries.map(\.id) == ["turn:file-change-summary"])
		if case .fileChanges(
			let changes,
			_
		) = summaries.first?.activity
		{
			#expect(changes.map(\.diff) == ["@@ -1,1 +1,1 @@\n-before\n+after"])
		}
		else
		{
			Issue.record("Prepared summary was lost during work folding")
		}
	}
	private func change(
		path: String = "file.swift",
		kind: String = "update",
		movePath: String? = nil,
		diff: String
	) -> FileChange
	{
		var metadata: [String: String] = ["type": kind]
		metadata["move_path"] = movePath
		return FileChange(json: ["path": path, "kind": metadata, "diff": diff])!
	}
}
