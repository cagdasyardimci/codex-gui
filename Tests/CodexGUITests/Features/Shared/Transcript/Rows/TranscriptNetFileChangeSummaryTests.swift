import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptNetFileChangeSummaryTests
{

	@Test(arguments: [false, true])
	func temporaryCopyEditsNeverEnterCardOrItsTotals(prepared: Bool) async throws
	{
		let entries = [ConversationEntry(
			id: "turn:edit",
			kind: .tool,
			title: "Changed files",
			body: "",
			activity: .fileChanges(
				[
					change(
						path: "/tmp/codex-gui-send.copy/File.swift",
						diff: "@@ -1 +1,2 @@\n-old\n+copy\n+extra"
					),
					change(
						path: "File.swift",
						diff: "@@ -1 +1 @@\n-old\n+new"
					),
				],
				status: "completed"
			)
		)]
		let sources = TranscriptPreparationCoordinator.fileChangeSources(
			from: entries,
			repositoryRoot: "/workspace/repo"
		)
		#expect(sources.first?.changes.map(\.path) == ["File.swift"])
		let cache = ConversationNetFileChangePreparation()
		let netChanges = prepared ? await cache.prepare(
			sources,
			context: "thread"
		) : nil
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: [ConversationTurnTiming(
				turnID: "turn",
				status: "completed"
			)],
			projectPath: "/workspace/repo",
			preparedNetChanges: netChanges ?? [:]
		)
		let summary = try #require(rows.first)
		guard case .message(let entry) = summary,
				case .fileChanges(
				let changes,
				_
				) = entry.activity
		else
		{
			Issue.record("Expected repository edit card")
			return
		}
		#expect(changes.map(\.path) == ["File.swift"])
		let counts = GitDiffParser.hunks(
			in: changes.map(\.diff).joined(separator: "\n").components(separatedBy: "\n")
		)
		#expect(counts.additions == 1)
		#expect(counts.deletions == 1)
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
