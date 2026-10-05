import Foundation
import Testing

@testable import CodexGUI

struct ConversationSubagentsTests
{
	@Test func lifecycleUpdatesPreserveIdentityNameAndFirstOccurrenceOrder()
	{
		let projection = ConversationSubagents(entries: [
			entry(
				"first",
				kind: "started",
				thread: "one",
				path: "/root/app_client"
			),
			entry(
				"second",
				kind: "started",
				thread: "two",
				path: "/root/reducers"
			),
			entry(
				"third",
				kind: "completed",
				thread: "one"
			),
		])
		#expect(projection.agents.map(\.identity) == ["one", "two"])
		#expect(projection.agents.map(\.name) == ["App Client", "Reducers"])
		#expect(projection.doneAgents.map(\.identity) == ["one"])
		#expect(projection.activeAgents.map(\.identity) == ["two"])
		let summary = projection.summary(parentThreadID: "parent")
		#expect(summary.completedCount == 1)
		#expect(summary.runningCount == 1)
		#expect(summary.identities.map(\.parentThreadID) == ["parent", "parent"])
	}

	@Test func observationsCannotFinishOrRestartAnAgent()
	{
		let projection = ConversationSubagents(entries: [
			entry(
				"start",
				kind: "started",
				thread: "one"
			),
			entry(
				"unknown",
				kind: "future-event",
				thread: "one"
			),
			entry(
				"done",
				kind: "completed",
				thread: "two"
			),
			entry(
				"input",
				kind: "interacted",
				thread: "two"
			),
			entry(
				"unknown-done",
				kind: "unknown",
				thread: "two"
			),
		])
		#expect(projection.activeAgents.map(\.identity) == ["one"])
		#expect(projection.doneAgents.map(\.identity) == ["two"])
		#expect(projection.status(for: projection.agents[1]) == .completed)
	}

	@Test func restartAndExceptionalTerminalOutcomesRemainDistinct()
	{
		let projection = ConversationSubagents(entries: [
			entry(
				"failed",
				kind: "failed",
				thread: "one"
			),
			entry(
				"restart",
				kind: "started",
				thread: "one"
			),
			entry(
				"interrupted",
				kind: "interrupted",
				thread: "two"
			),
			entry(
				"other-failed",
				kind: "failed",
				thread: "three"
			),
		])
		#expect(projection.status(for: projection.agents[0]) == .active)
		#expect(projection.status(for: projection.agents[1]) == .interrupted)
		#expect(projection.status(for: projection.agents[2]) == .failed)
	}

	@Test func pathFallbackCanGainThreadIdentityWithoutMergingDistinctThreads()
	{
		let projection = ConversationSubagents(entries: [
			entry(
				"path",
				kind: "started",
				path: "/root/task"
			),
			entry(
				"thread",
				kind: "completed",
				thread: "one",
				path: "/root/task"
			),
			entry(
				"new",
				kind: "started",
				thread: "two",
				path: "/root/task"
			),
		])
		#expect(projection.agents.map(\.identity) == ["one", "two"])
		#expect(projection.doneAgents.map(\.identity) == ["one"])
	}

	private func entry(
		_ id: String,
		kind: String,
		thread: String? = nil,
		path: String? = nil,
		completedAt: Date? = nil,
		startedAt: Date? = nil
	) -> ConversationEntry
	{
		return ConversationEntry(
			id: id,
			kind: .tool,
			title: "Subagent",
			body: "",
			activity: .subagent(CodexSubagentActivity(
				kind: kind,
				threadID: thread,
				path: path,
				completedAt: completedAt,
				startedAt: startedAt
			))
		)
	}

	@Test func lifecycleTimesSurviveObservationsButResetOnRestart()
	{
		let startedAt = Date(timeIntervalSince1970: 100)
		let completedAt = Date(timeIntervalSince1970: 200)
		let restartAt = Date(timeIntervalSince1970: 300)
		let entries = [
			entry(
				"start",
				kind: "started",
				thread: "one",
				startedAt: startedAt
			),
			entry(
				"done",
				kind: "completed",
				thread: "one",
				completedAt: completedAt
			),
			entry(
				"input",
				kind: "interacted",
				thread: "one"
			),
			entry(
				"unknown",
				kind: "new-kind",
				thread: "one"
			),
		]
		let completed = ConversationSubagents(entries: entries)
		#expect(completed.completedAt(for: completed.agents[0]) == completedAt)
		#expect(completed.startedAt(for: completed.agents[0]) == startedAt)
		let restarted = ConversationSubagents(entries: entries + [entry(
			"restart",
			kind: "started",
			thread: "one",
			startedAt: restartAt
		)])
		#expect(restarted.completedAt(for: restarted.agents[0]) == nil)
		#expect(restarted.startedAt(for: restarted.agents[0]) == restartAt)
		let untimedRestart = ConversationSubagents(entries: entries + [entry(
			"restart",
			kind: "started",
			thread: "one"
		)])
		#expect(untimedRestart.startedAt(for: untimedRestart.agents[0]) == nil)
	}

	@Test func decodedHistoricalActivityHasNoInventedTimestamps()
	{
		let activity = CodexSubagentActivity(json: [
			"kind": "completed",
			"agentThreadId": "one",
			"agentPath": "/root/task",
			"completedAt": 200,
		])
		#expect(activity.completedAt == nil)
		#expect(activity.startedAt == nil)
	}
}
