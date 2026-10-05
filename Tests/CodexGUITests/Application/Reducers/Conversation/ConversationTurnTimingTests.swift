import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct ConversationTurnTimingTests
{
	@Test(arguments: ["inProgress", "running"])
	func liveObservationsKeepOwnerStartAndFreezeAcrossHistoryRefresh(status: String)
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/timing"
		))
		model.conversations.selectedConversation = .thread("other")
		let start = Date(timeIntervalSince1970: 1000)
		let active = CodexTurn(
			id: "turn",
			status: status,
			items: [],
			error: nil
		)
		for offset in [0.0, 10.0]
		{
			ConversationContentReducer.observe(
				.turnStarted(
					threadId: "owner",
					turn: active
				),
				model: &model,
				observedAt: start.addingTimeInterval(offset)
			)
		}
		#expect(model.conversations.content[.thread("owner")]?
			.turnTimings["turn"]?.startedAt == start)
		#expect(model.conversations.content[.thread("owner")]?
			.turnTimings["turn"]?.completedAt == nil)
		#expect(model.conversations.content[.thread("other")] == nil)
		let older = CodexTurn(
			id: "older",
			status: "completed",
			items: [],
			error: nil
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "owner",
				turn: older
			),
			model: &model,
			observedAt: start.addingTimeInterval(20)
		)
		let summary = ThreadSummary(json: ["id": "owner", "cwd": "/tmp/timing"])!
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [older],
				nextTurnsCursor: nil
			),
			model: &model
		)
		#expect(model.conversations.content[.thread("owner")]?.latestObservedGitTurnID == "turn")
		var displayedModel = model
		displayedModel.conversations.selectedConversation = .thread("owner")
		displayedModel.execution.activeThreadID = "owner"
		displayedModel.execution.activeTurnID = "older"
		displayedModel.execution.state = .running
		#expect(WorkspaceSelectors(
			model: displayedModel,
			now: start.addingTimeInterval(30)
		).lastGitTurnID == "turn")
		let completed = CodexTurn(
			id: "turn",
			status: "completed",
			items: [],
			error: nil
		)
		ConversationContentReducer.observe(
			.turnCompleted(
				threadId: "owner",
				turn: completed
			),
			model: &model,
			observedAt: start.addingTimeInterval(48)
		)
		ConversationContentReducer.merge(
			ThreadDetail(
				summary: summary,
				turns: [completed],
				nextTurnsCursor: nil
			),
			model: &model
		)
		let content = model.conversations.content[.thread("owner")]!
		let timing = ConversationContentReducer.timings(for: content).first!
		#expect(timing.startedAt == start)
		#expect(timing.completedAt == start.addingTimeInterval(48))
		#expect(ConversationTurnStatusCollectionItem.statusText(
			timing: timing,
			now: start.addingTimeInterval(999)
		) == "Worked for 48s")
	}

	@Test func historicalTurnsDoNotInventTimingAndBackendValuesTakePriority()
	{
		let start = Date(timeIntervalSince1970: 1000)
		let history = CodexTurn(
			id: "history",
			status: "completed",
			items: [],
			error: nil
		)
		let historicalTiming = ConversationTurnTiming(turn: history)
		#expect(historicalTiming.startedAt == nil)
		#expect(historicalTiming.completedAt == nil)
		let runningHistory = CodexTurn(
			id: "running-history",
			status: "running",
			items: [],
			error: nil
		)
		let runningTiming = ConversationTurnTiming(turn: runningHistory)
		#expect(runningTiming.startedAt == nil)
		#expect(runningTiming.completedAt == nil)
		let backend = CodexTurn(
			id: "backend",
			status: "completed",
			items: [],
			error: nil,
			startedAt: start,
			completedAt: start.addingTimeInterval(20),
			durationMs: 19_000
		)
		let timing = ConversationTurnTiming(
			turn: backend,
			observedAt: start.addingTimeInterval(48)
		)
		#expect(timing.startedAt == backend.startedAt)
		#expect(timing.completedAt == backend.completedAt)
		#expect(timing.durationMs == backend.durationMs)
	}
}
