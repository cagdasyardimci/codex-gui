import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SubagentLifecycleTimingTests
{
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

	@Test func parentTurnCompletionAndUntimedHistoryCannotInventChildTimes() throws
	{
		var model = fixture()
		let done = try item(
			id: "done",
			kind: "completed"
		)
		let turn = CodexTurn(
			id: "turn",
			status: "completed",
			items: [done],
			error: nil
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "parent",
				turn: turn
			),
			model: &model,
			observedAt: Date(timeIntervalSince1970: 500)
		)
		let replay = projection(model)
		#expect(replay.completedAt(for: replay.agents[0]) == nil)
		observe(
			done,
			model: &model,
			at: nil
		)
		#expect(projection(model).agents[0].completedAt == nil)
		try merge(
			[done],
			model: &model
		)
		#expect(projection(model).agents[0].completedAt == nil)
	}

	@Test func rereadCannotMoveTimingToAnotherChildOrLifecycleKind() throws
	{
		var model = fixture()
		observe(
			try item(
				id: "same",
				kind: "completed"
			),
			model: &model,
			at: Date(timeIntervalSince1970: 200)
		)
		try merge(
			[try item(
				id: "same",
				kind: "completed",
				child: "different"
			)],
			model: &model
		)
		#expect(projection(model).agents[0].completedAt == nil)
		observe(
			try item(
				id: "same",
				kind: "completed",
				child: "different"
			),
			model: &model,
			at: Date(timeIntervalSince1970: 300)
		)
		try merge(
			[try item(
				id: "same",
				kind: "started",
				child: "different"
			)],
			model: &model
		)
		#expect(projection(model).agents[0].completedAt == nil)
		#expect(projection(model).agents[0].startedAt == nil)
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
