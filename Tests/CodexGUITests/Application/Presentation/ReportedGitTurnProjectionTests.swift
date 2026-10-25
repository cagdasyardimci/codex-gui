import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ReportedGitTurnProjectionTests
{

	@Test func olderOrUndatedHistoryCannotRollBackCanonicalEditingIdentity()
	{
		var value = model()
		merge(
			[turn(
				"latest",
				items: [fileItem("latest")],
				startedAt: 20
			)],
			into: &value
		)
		merge(
			[turn(
				"old",
				items: [fileItem("old")],
				startedAt: 10
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
		merge(
			[turn(
				"undated",
				items: [fileItem("undated")]
			)],
			into: &value
		)
		#expect(snapshot(value).reportedGitTurnID == "latest")
		#expect(snapshot(value).reportedGitChanges == nil)
	}

	private func model() -> WorkspaceModel
	{
		var value = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/reported-git-turn"
		))
		value.conversations.selectedConversation = .thread("thread")
		return value
	}

	private func snapshot(_ value: WorkspaceModel) -> ConversationSnapshot
	{
		WorkspaceSelectors(
			model: value,
			now: .distantPast
		).makeSnapshot()
	}

	private func merge(
		_ turns: [CodexTurn],
		into value: inout WorkspaceModel
	)
	{
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: ThreadSummary(json: ["id": "thread", "cwd": "/tmp/reported-git-turn"])!,
				turns: turns,
				nextTurnsCursor: nil
			),
			model: &value
		)
	}

	private func removeResidentTurn(
		_ id: String,
		from value: inout WorkspaceModel
	)
	{
		ConversationContentReducer.updateContent(
			for: "thread",
			model: &value
		)
		{
			$0.loadedTurns.removeAll
			{
				$0.id == id
			}
			$0.entries.removeAll
			{
				$0.id.hasPrefix(id + ":")
			}
		}
	}

	private func turn(
		_ id: String,
		items: [CodexItem] = [],
		status: String = "completed",
		startedAt: TimeInterval? = nil,
		itemsAreComplete: Bool = true
	) -> CodexTurn
	{
		CodexTurn(
			id: id,
			status: status,
			items: items,
			error: nil,
			startedAt: startedAt.map
			{
				Date(timeIntervalSince1970: $0)
			},
			itemsAreComplete: itemsAreComplete
		)
	}

	private func fileItem(
		_ id: String,
		path: String = "file.swift",
		status: String = "completed",
		changes: [[String: Any]]? = nil
	) -> CodexItem
	{
		CodexItem(json: [
			"id": id,
			"type": "fileChange",
			"status": status,
			"changes": changes ?? [[
				"path": path,
				"kind": "update",
				"diff": "@@ -1 +1 @@\n-old\n+new\n",
			]],
		])!
	}
}
