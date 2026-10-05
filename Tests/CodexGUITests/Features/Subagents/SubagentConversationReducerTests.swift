import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct SubagentConversationReducerTests
{
	@Test func selectingAndReturningToListRejectsRetainedReadResponses() throws
	{
		var state = SubagentConversationState()
		#expect(reduce(
			&state,
			.select(
				agent(),
				requestID: 1
			)
		) == [
			.cancel,
			.read(
				threadID: "child",
				requestID: 1
			),
		])
		#expect(state.selectedThreadID == "child")
		#expect(state.isLoading)
		#expect(reduce(
			&state,
			.back
		) == [.cancel])
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: try detail(
					"child",
					text: "stale"
				)
			)
		)
		#expect(state.agent == nil)
		#expect(state.entries.isEmpty)
		#expect(!state.isLoading)
		_ = reduce(
			&state,
			.select(
				agent(),
				requestID: 2
			)
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: try detail(
					"child",
					text: "stale"
				)
			)
		)
		#expect(state.isLoading)
		#expect(state.entries.isEmpty)
		_ = reduce(
			&state,
			.loaded(
				requestID: 2,
				detail: try detail(
					"wrong",
					text: "wrong"
				)
			)
		)
		#expect(state.isLoading)
		#expect(state.entries.isEmpty)
	}

	@Test func paginationPreservesCurrentRowsAndRefreshRetainsEarlierPages() throws
	{
		var state = SubagentConversationState()
		_ = reduce(
			&state,
			.select(
				agent(),
				requestID: 1
			)
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: try detail(
					"child",
					text: "latest"
				)
			)
		)
		#expect(reduce(
			&state,
			.loadEarlier(requestID: 2)
		) == [
			.earlier(
				threadID: "child",
				cursor: "older",
				requestID: 2
			),
		])
		let older = try turn(
			id: "older-turn",
			text: "earlier"
		)
		let overlap = try turn(
			id: "turn",
			text: "old snapshot"
		)
		_ = reduce(
			&state,
			.earlierLoaded(
				requestID: 2,
				turns: [older, overlap],
				nextCursor: nil
			)
		)
		#expect(state.entries.map(\.body) == ["earlier", "latest"])
		_ = reduce(
			&state,
			.refresh(requestID: 3)
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 3,
				detail: try detail(
					"child",
					text: "updated"
				)
			)
		)
		#expect(state.entries.map(\.body) == ["earlier", "updated"])
		#expect(state.nextCursor == nil)
		#expect(!state.isLoading)
	}

	@Test func refreshReplacesWholeTurnAndRemovesObsoleteItems() throws
	{
		var state = SubagentConversationState()
		_ = reduce(
			&state,
			.select(
				agent(),
				requestID: 1
			)
		)
		var loaded = try detail(
			"child",
			text: "current"
		)
		let oldTurn = try #require(CodexTurn(json: [
			"id": "turn",
			"status": "completed",
			"items": [
				["id": "message", "type": "agentMessage", "text": "current"],
				["id": "obsolete", "type": "agentMessage", "text": "removed later"],
			],
		]))
		loaded = ThreadDetail(
			summary: loaded.summary,
			turns: [oldTurn],
			nextTurnsCursor: "older"
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: loaded
			)
		)
		_ = reduce(
			&state,
			.loadEarlier(requestID: 2)
		)
		_ = reduce(
			&state,
			.earlierLoaded(
				requestID: 2,
				turns: [try turn(
					id: "older-turn",
					text: "earlier"
				)],
				nextCursor: nil
			)
		)
		_ = reduce(
			&state,
			.refresh(requestID: 3)
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 3,
				detail: try detail(
					"child",
					text: "updated"
				)
			)
		)
		#expect(state.entries.map(\.body) == ["earlier", "updated"])
		#expect(state.loadedTurns.map(\.id) == ["older-turn", "turn"])
	}

	@Test func refreshRetainsTurnsThatAgeOutOfLatestPage() throws
	{
		var state = SubagentConversationState()
		_ = reduce(
			&state,
			.select(
				agent(),
				requestID: 1
			)
		)
		let initial = try detail(
			"child",
			text: "retained turn"
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: initial
			)
		)
		_ = reduce(
			&state,
			.refresh(requestID: 2)
		)
		let currentPage = ThreadDetail(
			summary: initial.summary,
			turns: [try turn(
				id: "new-turn",
				text: "latest turn"
			)],
			nextTurnsCursor: "older"
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 2,
				detail: currentPage
			)
		)
		#expect(state.entries.map(\.body) == ["retained turn", "latest turn"])
	}

	@Test func failureRetainsContentAndPaginationRetryUsesFailedCursor() throws
	{
		var state = SubagentConversationState()
		_ = reduce(
			&state,
			.select(
				agent(),
				requestID: 1
			)
		)
		_ = reduce(
			&state,
			.loaded(
				requestID: 1,
				detail: try detail(
					"child",
					text: "current"
				)
			)
		)
		_ = reduce(
			&state,
			.loadEarlier(requestID: 2)
		)
		_ = reduce(
			&state,
			.failed(
				requestID: 2,
				message: "Offline",
				paginationCursor: "older"
			)
		)
		#expect(state.error == "Offline")
		#expect(state.entries.map(\.body) == ["current"])
		#expect(reduce(
			&state,
			.retry(requestID: 3)
		) == [
			.earlier(
				threadID: "child",
				cursor: "older",
				requestID: 3
			),
		])
		#expect(state.error == nil)
		#expect(state.isLoading)
	}

	@Test func agentsWithoutThreadIdentifiersDoNotStartReads()
	{
		var state = SubagentConversationState()
		let missing = CodexSubagentActivity(json: ["agentPath": "/root/missing"])
		#expect(reduce(
			&state,
			.select(
				missing,
				requestID: 1
			)
		).isEmpty)
		#expect(state.agent == nil)
		#expect(state.entries.isEmpty)
		#expect(!state.isLoading)
	}

	private func reduce(
		_ state: inout SubagentConversationState,
		_ action: SubagentConversationReducer.Action
	) -> [SubagentConversationReducer.Effect]
	{
		SubagentConversationReducer.reduce(
			&state,
			action
		)
	}

	private func agent() -> CodexSubagentActivity
	{
		CodexSubagentActivity(json: ["agentThreadId": "child", "agentPath": "/root/child"])
	}

	private func detail(
		_ threadID: String,
		text: String
	) throws -> ThreadDetail
	{
		ThreadDetail(
			summary: try #require(ThreadSummary(json: ["id": threadID, "cwd": "/tmp"])),
			turns: [try turn(
				id: "turn",
				text: text
			)],
			nextTurnsCursor: "older"
		)
	}

	private func turn(
		id: String,
		text: String
	) throws -> CodexTurn
	{
		try #require(CodexTurn(json: [
			"id": id,
			"status": "completed",
			"items": [["id": "message", "type": "agentMessage", "text": text]],
		]))
	}
}
