import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SubagentLifecycleTimingTests
{
	@Test(arguments: ["completed", "failed", "interrupted"])
	func followUpResumesTerminalAgentAndLaterCompletionRemainsAuthoritative(
		terminalKind: String
	) throws
	{
		var model = fixture()
		let start = try item(
			id: "start",
			kind: "started"
		)
		let terminal = try item(
			id: "terminal",
			kind: terminalKind
		)
		let followUp = try item(
			id: "follow-up",
			kind: "interacted"
		)
		let resumedAt = Date(timeIntervalSince1970: 300)
		observe(
			start,
			model: &model,
			at: Date(timeIntervalSince1970: 100)
		)
		observe(
			terminal,
			model: &model,
			at: Date(timeIntervalSince1970: 200)
		)
		#expect(projection(model).doneAgents.count == 1)
		observe(
			followUp,
			model: &model,
			at: resumedAt
		)
		let resumed = projection(model)
		let agent = try #require(resumed.activeAgents.first)
		#expect(resumed.agents.count == 1)
		#expect(resumed.doneAgents.isEmpty)
		#expect(resumed.status(for: agent) == .active)
		#expect(resumed.completedAt(for: agent) == nil)
		#expect(resumed.startedAt(for: agent) == resumedAt)
		#expect(resumed.summary(parentThreadID: "parent").runningCount == 1)
		try merge(
			[start, terminal, followUp],
			model: &model
		)
		#expect(projection(model) == resumed)
		observe(
			try item(
				id: "more-input",
				kind: "interacted"
			),
			model: &model,
			at: Date(timeIntervalSince1970: 400)
		)
		#expect(projection(model).startedAt(for: agent) == resumedAt)
		let done = try item(
			id: "done",
			kind: "completed"
		)
		let completedAt = Date(timeIntervalSince1970: 500)
		observe(
			done,
			model: &model,
			at: completedAt
		)
		let completed = projection(model)
		#expect(completed.activeAgents.isEmpty)
		#expect(completed.status(for: agent) == .completed)
		#expect(completed.completedAt(for: agent) == completedAt)
		#expect(completed.startedAt(for: agent) == resumedAt)
	}

	@Test func directLifecycleEventsCaptureSuppliedTimeAndRereadsRetainIt() throws
	{
		var model = fixture()
		let startedAt = Date(timeIntervalSince1970: 100)
		let completedAt = Date(timeIntervalSince1970: 200)
		let start = try item(
			id: "start",
			kind: "started"
		)
		let done = try item(
			id: "done",
			kind: "completed"
		)
		observe(
			start,
			model: &model,
			at: startedAt
		)
		observe(
			done,
			model: &model,
			at: completedAt
		)
		observe(
			done,
			model: &model,
			at: Date(timeIntervalSince1970: 900)
		)
		let beforeRead = projection(model)
		#expect(beforeRead.startedAt(for: beforeRead.agents[0]) == startedAt)
		#expect(beforeRead.completedAt(for: beforeRead.agents[0]) == completedAt)
		try merge(
			[start, done],
			model: &model
		)
		let afterRead = projection(model)
		#expect(afterRead.startedAt(for: afterRead.agents[0]) == startedAt)
		#expect(afterRead.completedAt(for: afterRead.agents[0]) == completedAt)
		let restart = try item(
			id: "restart",
			kind: "started"
		)
		observe(
			restart,
			model: &model,
			at: Date(timeIntervalSince1970: 300)
		)
		let restarted = projection(model)
		#expect(restarted.completedAt(for: restarted.agents[0]) == nil)
		#expect(restarted.startedAt(for: restarted.agents[0]) == Date(timeIntervalSince1970: 300))
	}

	private func fixture() -> WorkspaceModel
	{
		WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/subagent-timing"
		))
	}

	private func item(
		id: String,
		kind: String,
		child: String = "child"
	) throws -> CodexItem
	{
		try #require(CodexItem(json: [
			"id": id,
			"type": "subAgentActivity",
			"kind": kind,
			"agentThreadId": child,
			"agentPath": "/root/task",
		]))
	}

	private func observe(
		_ item: CodexItem,
		model: inout WorkspaceModel,
		at date: Date?
	)
	{
		ConversationContentReducer.observe(
			.itemCompleted(
				threadId: "parent",
				turnId: "turn",
				item: item
			),
			model: &model,
			observedAt: date
		)
	}

	private func projection(_ model: WorkspaceModel) -> ConversationSubagents
	{
		ConversationSubagents(entries: model.conversations.content[.thread("parent")]?
			.entries ?? [])
	}

	private func merge(
		_ items: [CodexItem],
		model: inout WorkspaceModel
	) throws
	{
		let summary = try #require(ThreadSummary(json: ["id": "parent"]))
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [CodexTurn(
					id: "turn",
					status: "completed",
					items: items,
					error: nil
				)],
				nextTurnsCursor: nil
			),
			model: &model
		)
	}
}
