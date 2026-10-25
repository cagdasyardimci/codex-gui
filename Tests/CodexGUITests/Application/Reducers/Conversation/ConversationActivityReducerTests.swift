import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ConversationActivityReducerTests
{
	private func model() -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/activity"
		))
		model.conversations.selectedConversation = .thread("viewed")
		return model
	}

	private func command(
		status: String,
		output: String? = nil
	) -> CodexItem
	{
		var json: [String: Any] = [
			"id": "command",
			"type": "commandExecution",
			"command": "cat src/file",
			"cwd": "/tmp/activity",
			"status": status,
			"commandActions": [[
				"type": "read",
				"command": "cat src/file",
				"name": "file",
				"path": "src/file"
			]]
		]
		json["aggregatedOutput"] = output
		if status == "completed"
		{
			json["exitCode"] = 0
			json["durationMs"] = 25
		}
		return CodexItem(json: json)!
	}

	private func observe(
		_ event: AppServerEvent,
		model: inout WorkspaceModel
	)
	{
		ConversationContentReducer.observe(
			event,
			model: &model
		)
	}

	@Test func turnCompletionAndHistoryProduceTheSameCommandAndImageEntries() throws
	{
		var live = model()
		let image = CodexItem(json: [
			"id": "image",
			"type": "imageView",
			"path": "/tmp/image.png"
		])!
		let final = command(
			status: "completed",
			output: "done"
		)
		let turn = CodexTurn(
			id: "turn",
			status: "completed",
			items: [final, image],
			error: nil,
			startedAt: Date(timeIntervalSince1970: 100),
			completedAt: Date(timeIntervalSince1970: 103),
			durationMs: 3_000
		)
		observe(
			.itemStarted(
				threadId: "worker",
				turnId: "turn",
				item: command(status: "inProgress")
			),
			model: &live
		)
		observe(
			.turnCompleted(
				threadId: "worker",
				turn: turn
			),
			model: &live
		)
		var history = model()
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: ThreadSummary(json: ["id": "worker", "cwd": "/tmp/activity"])!,
				turns: [turn],
				nextTurnsCursor: nil
			),
			model: &history
		)
		let liveContent = live.conversations.content[.thread("worker")]!
		let historyContent = history.conversations.content[.thread("worker")]!
		#expect(liveContent.entries == historyContent.entries)
		let completedEntry = try #require(liveContent.entries.first)
		#expect(completedEntry.body == "$ cat src/file\ndone")
		#expect(completedEntry.title == "Command · completed")
		guard case .command(let completedActivity) = completedEntry.activity
		else
		{
			Issue.record("Expected completed command activity")
			return
		}
		#expect(completedActivity.output == "done")
		#expect(completedActivity.status == "completed")
		#expect(completedActivity.exitCode == 0)
		#expect(completedActivity.durationMs == 25)
		#expect(liveContent.entries[1].activity == .image(path: "/tmp/image.png"))
		#expect(ConversationContentReducer.timings(for: liveContent) ==
			ConversationContentReducer.timings(for: historyContent))
	}

	@Test func snapshotPreservesExecutionTurnOwnershipAcrossConversationSelection()
	{
		var value = model()
		var execution = ExecutionModel()
		execution.activeThreadID = "worker"
		execution.activeTurnID = "live"
		execution.state = .running
		value.executions.entries[.thread("worker")] = execution
		let oldTurn = CodexTurn(
			id: "historical",
			status: "inProgress",
			items: [],
			error: nil,
			startedAt: Date(timeIntervalSince1970: 1)
		)
		observe(
			.turnStarted(
				threadId: "viewed",
				turn: oldTurn
			),
			model: &value
		)
		let viewed = WorkspaceSelectors(
			model: value,
			now: Date(timeIntervalSince1970: 101)
		).makeSnapshot()
		#expect(viewed.activeThreadID == nil)
		#expect(viewed.activeTurnID == nil)
		#expect(viewed.activeExecutionState == nil)
		#expect(value.execution(for: .thread("worker")).state == .running)
		#expect(viewed.turnTimings.map(\.turnID) == ["historical"])
		value.conversations.selectedConversation = .thread("worker")
		let worker = WorkspaceSelectors(
			model: value,
			now: Date(timeIntervalSince1970: 102)
		).makeSnapshot()
		#expect(worker.activeThreadID == "worker")
		#expect(worker.activeTurnID == "live")
		#expect(worker.turnTimings.isEmpty)
	}

}
