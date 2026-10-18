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
		let timings = [ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			startedAt: Date(timeIntervalSince1970: 1_000)
		)]
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: timings,
			projectPath: nil,
			preparedNetChanges: prepared ?? [:]
		)
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
		#expect(rows.suffix(3).map(\.id)
			== ["turn:reply", "turn:file-change-summary", "next:request"])
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
	@Test(arguments: [
		"inProgress",
		"running",
		"unknown",
		"completed",
		"failed",
		"interrupted",
		"stopped",
		"cancelled",
		"missing",
	])
	func editCardWaitsForItsOwnTurnToEnd(status: String)
	{
		let entries = [
			ConversationEntry(
				id: "previous:edit",
				kind: .tool,
				title: "Changed file",
				body: "",
				activity: .fileChanges(
					[change(diff: "@@ -1 +1 @@\n-old\n+previous")],
					status: "completed"
				)
			),
			ConversationEntry(
				id: "turn:edit",
				kind: .tool,
				title: "Changed file",
				body: "",
				activity: .fileChanges(
					[change(diff: "@@ -1 +1 @@\n-previous\n+new")],
					status: "completed"
				)
			),
			ConversationEntry(
				id: "turn:comment",
				kind: .agent,
				title: "Codex",
				body: "Checking the edit"
			),
		]
		var timings = [ConversationTurnTiming(
			turnID: "previous",
			status: "completed"
		)]
		if status != "missing"
		{
			timings.append(ConversationTurnTiming(
				turnID: "turn",
				status: status
			))
		}
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: timings,
			projectPath: nil
		)
		let terminal = ["completed", "failed", "interrupted", "stopped", "cancelled"]
			.contains(status)
		let expected = ["previous:file-change-summary", "turn:comment"]
			+ (terminal ? ["turn:file-change-summary"] : [])
		#expect(rows.map(\.id) == expected)
	}

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

	@Test(arguments: ["completed", "failed"])
	func temporaryOnlyTurnHasNoChangeCard(status: String)
	{
		let entry = ConversationEntry(
			id: "turn:edit",
			kind: .tool,
			title: "Changed files",
			body: "",
			activity: .fileChanges(
				[
					change(
						path: "/tmp/copy/File.swift",
						diff: "@@ -1 +1 @@\n-old\n+new"
					),
				],
				status: status
			)
		)
		let rows = ConversationTranscriptRow.make(
			entries: [entry],
			timings: [ConversationTurnTiming(
				turnID: "turn",
				status: "completed"
			)],
			projectPath: "/workspace/repo"
		)
		#expect(rows.isEmpty)
	}

	@Test func equivalentReportPathsSharePreparedTranscriptIdentityAndNetTotals() async throws
	{
		let paths = ["File.swift",
						"./File.swift",
						"folder/../File.swift",
						"/workspace/repo/File.swift"]
		let values = ["original", "one", "two", "three", "final"]
		let changes = paths.enumerated().map
		{
			index, path in
			change(
				path: path,
				diff: "@@ -1 +1 @@\n-\(values[index])\n+\(values[index + 1])"
			)
		}
		let entries = [ConversationEntry(
			id: "turn:edit",
			kind: .tool,
			title: "Changed files",
			body: "",
			activity: .fileChanges(
				changes,
				status: "completed"
			)
		)]
		let sources = TranscriptPreparationCoordinator.fileChangeSources(
			from: entries,
			repositoryRoot: "/workspace/repo"
		)
		let prepared = await ConversationNetFileChangePreparation().prepare(
			sources,
			context: "thread"
		)
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: [ConversationTurnTiming(
				turnID: "turn",
				status: "completed"
			)],
			projectPath: "/workspace/repo",
			preparedNetChanges: prepared ?? [:]
		)
		let row = try #require(rows.first)
		guard case .message(let entry) = row, case .fileChanges(
			let projected,
			_
		) = entry.activity
		else
		{
			Issue.record("Expected the prepared normalized change card")
			return
		}
		#expect(projected.map(\.path) == ["File.swift"])
		#expect(projected.map(\.diff) == ["@@ -1,1 +1,1 @@\n-original\n+final"])
		#expect(changes.map(\.path) == paths)
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
