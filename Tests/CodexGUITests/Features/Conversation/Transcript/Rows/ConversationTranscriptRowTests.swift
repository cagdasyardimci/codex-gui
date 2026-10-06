import Foundation
import Testing

@testable import CodexGUI

struct ConversationTranscriptRowTests
{
	@Test func liveClockAppearsBeforeFirstItemAndIsNotDuplicatedWhenReplyArrives()
	{
		let timing = ConversationTurnTiming(
			turnID: "turn",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1000)
		)
		let user = ConversationEntry(
			id: "local:request",
			kind: .user,
			title: "You",
			body: "Request"
		)
		#expect(ConversationTranscriptRow.make(
			entries: [user],
			timings: [timing],
			projectPath: nil
		) == [.message(user), .turnStatus(timing)])
		let reply = ConversationEntry(
			id: "turn:reply",
			kind: .agent,
			title: "Codex",
			body: "Reply"
		)
		#expect(ConversationTranscriptRow.make(
			entries: [user, reply],
			timings: [timing],
			projectPath: nil
		) == [.message(user), .turnStatus(timing), .message(reply)])
		#expect(ConversationTranscriptRow.make(
			entries: [],
			timings: [timing],
			projectPath: nil
		) == [.turnStatus(timing)])
	}

	@Test func groupsPreserveDuplicateReadsAndBreakAtCommentaryAndImages()
	{
		let read = CodexCommandAction(
			kind: .read,
			command: "cat file",
			name: "file",
			path: "file"
		)
		let first = commandEntry(
			"turn:a",
			actions: [read, read]
		)
		let second = commandEntry(
			"turn:b",
			actions: []
		)
		let comment = ConversationEntry(
			id: "turn:c",
			kind: .agent,
			title: "Codex",
			body: "Update"
		)
		let image = ConversationEntry(
			id: "turn:d",
			kind: .tool,
			title: "Image",
			body: "",
			activity: .image(path: "/tmp/image.png")
		)
		let rows = ConversationTranscriptRow.make(
			entries: [first, second, comment, image, commandEntry(
				"turn:e",
				actions: []
			)],
			projectPath: "/project",
			expandedGroupIDs: ["activity-group:turn:a"]
		)
		let activities = rows.compactMap
		{
			row -> ConversationActivityRow? in
			guard case .activity(let activity) = row
			else
			{
				return nil
			}
			return activity
		}
		#expect(activities.map(\.kind) == [
			.group,
			.read,
			.read,
			.command,
			.image,
			.command
		])
		#expect(activities[0].title == "Read files, ran commands")
		#expect(activities[1].filePath == "/tmp/work/file")
		#expect(activities[1].sourceEntryID == activities[2].sourceEntryID)
		#expect(activities[1].id != activities[2].id)
		#expect(activities[4].expanded)
	}

	@Test func unknownActionUsesDecodedCommandAndExpansionDoesNotRequireOutput()
	{
		let entry = commandEntry(
			"turn:a",
			actions: [CodexCommandAction(
				kind: .unknown,
				command: "rg pattern file"
			)]
		)
		let rows = ConversationTranscriptRow.make(
			entries: [entry],
			projectPath: nil,
			expandedActivityIDs: [entry.id]
		)
		guard case .activity(let action) = rows.last
		else
		{
			Issue.record("Missing action")
			return
		}
		#expect(action.kind == .command)
		#expect(action.title == "Ran rg pattern file")
		#expect(action.expanded)
		#expect(action.command?.output == "")
		#expect(action.command?.command == "original shell")
	}

	@Test func collapsedGroupPreservesSourceTargetAndDifferentTurnsStartNewGroups()
	{
		let entries = [commandEntry(
			"one:a",
			actions: []
		), commandEntry(
			"two:b",
			actions: []
		)]
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: nil
		)
		#expect(rows.count == 2)
		#expect(rows[0].sourceEntryID == "one:a")
		#expect(rows[1].sourceEntryID == "two:b")
	}

	@Test func collapsedGroupCountsEachFailedSourceOnceAndPreviewFlattensWhitespace()
	{
		let read = CodexCommandAction(
			kind: .read,
			command: "cat file",
			path: "file"
		)
		let command = ConversationCommand(
			command: "python3  -\n  script",
			cwd: "/tmp",
			output: "",
			status: "completed",
			exitCode: 2,
			durationMs: nil,
			actions: [read, read, CodexCommandAction(
				kind: .unknown,
				command: "python3"
			)]
		)
		let entry = ConversationEntry(
			id: "turn:item",
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(command)
		)
		let collapsed = ConversationTranscriptRow.make(
			entries: [entry],
			projectPath: nil
		)
		guard case .activity(let group) = collapsed[0]
		else
		{
			return
		}
		#expect(group.title == "Read files, ran commands · 1 failed")
		#expect(collapsed.count == 1)
		#expect(!group.expanded)
		let expanded = ConversationTranscriptRow.make(
			entries: [entry],
			projectPath: nil,
			expandedGroupIDs: ["activity-group:turn:item"]
		)
		guard case .activity(let action) = expanded.last
		else
		{
			return
		}
		#expect(action.title == "Ran python3")
		#expect(action.command?.command == "python3  -\n  script")
	}

	@MainActor
	@Test func historyGroupsCommandsAcrossInvisibleItemsWithoutRepeatingSingletonHeaders() throws
	{
		// Mirrors the tail of Find codebase optimizations: commentary, commands,
		// hidden sleep/reasoning items, commentary, then another command group.
		let rawItems: [[String: Any]] = [
			["id": "before", "type": "agentMessage", "text": "Checking the final files."],
			[
				"id": "check",
				"type": "commandExecution",
				"command": "/bin/zsh -lc 'python3 check.py'",
				"commandActions": [["type": "unknown", "command": "python3 check.py"]]
			],
			["id": "reasoning", "type": "reasoning", "summary": []],
			["id": "after", "type": "agentMessage", "text": "Creating the commits."],
			[
				"id": "publish",
				"type": "commandExecution",
				"command": "/bin/zsh -lc 'python3 publish.py'",
				"commandActions": [["type": "unknown", "command": "python3 publish.py"]]
			],
			["id": "sleep", "type": "sleep", "durationMs": 30000],
			["id": "hidden", "type": "reasoning", "summary": []],
			["id": "status",
				"type": "commandExecution",
				"command": "/bin/zsh -lc 'git status'",
				"commandActions": [["type": "unknown", "command": "git status"]]],
			["id": "final", "type": "agentMessage", "text": "Committed."],
		]
		let history = try ConversationHistoryDecoder.decode(ProtocolJSONPayload(value: [
			"data": [["id": "turn", "status": "completed", "items": rawItems]],
		]))
		let entries = ConversationContentReducer.entries(for: history.turns)
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: nil,
			expandedGroupIDs: ["activity-group:turn:publish"]
		)
		#expect(rows.map(\.id) == [
			"turn:before",
			"turn:check",
			"turn:after",
			"activity-group:turn:publish",
			"turn:publish",
			"turn:status",
			"turn:final",
		])
		let activities = rows.compactMap
		{
			if case .activity(let activity) = $0
			{
				return activity
			}
			return nil as ConversationActivityRow?
		}
		#expect(activities.map(\.title) == [
			"Ran python3 check.py",
			"Ran commands",
			"Ran python3 publish.py",
			"Ran git status",
		])
		let collapsed = ConversationTranscriptRow.make(
			entries: entries,
			projectPath: nil
		)
		#expect(collapsed.map(\.id) == [
			"turn:before",
			"turn:check",
			"turn:after",
			"activity-group:turn:publish",
			"turn:final",
		])
	}

	@Test func duplicateTimingsKeepTheFirstMatchEvenWithoutAClock()
	{
		let first = ConversationTurnTiming(
			turnID: "first",
			status: "completed"
		)
		let laterFirst = ConversationTurnTiming(
			turnID: "first",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1000)
		)
		let second = ConversationTurnTiming(
			turnID: "second",
			status: "completed",
			durationMs: 2000
		)
		let laterSecond = ConversationTurnTiming(
			turnID: "second",
			status: "completed",
			durationMs: 9000
		)
		let firstRequest = messageEntry(
			"first:request",
			kind: .user
		)
		let firstReply = messageEntry("first:reply:part")
		let secondRequest = messageEntry(
			"second:request",
			kind: .user
		)
		let secondReply = messageEntry("second:reply")
		let rows = ConversationTranscriptRow.make(
			entries: [firstRequest, firstReply, secondRequest, secondReply],
			timings: [first, laterFirst, second, laterSecond],
			projectPath: nil
		)
		#expect(rows == [
			.message(firstRequest),
			.message(firstReply),
			.message(secondRequest),
			.turnStatus(second),
			.message(secondReply)
		])
	}

	@Test func timingPlacementPreservesMixedRowsMissingClocksAndTrailingRunningOrder()
	{
		let entries = [
			messageEntry(
				"user:request",
				kind: .user
			),
			commandEntry(
				"command:first",
				actions: []
			),
			commandEntry(
				"command:second",
				actions: []
			),
			ConversationEntry(
				id: "image:item",
				kind: .tool,
				title: "Image",
				body: "",
				activity: .image(path: "picture.png")
			),
			messageEntry(
				"missing:notice",
				kind: .notice
			),
			messageEntry("plain"),
			ConversationEntry(
				id: "empty:tool",
				kind: .tool,
				title: "Tool",
				body: "  \n"
			)
		]
		let clocks = ["image", "command", "user", "plain"].map
		{
			ConversationTurnTiming(
				turnID: $0,
				status: "completed",
				durationMs: 1000
			)
		}
		let empty = ConversationTurnTiming(
			turnID: "empty",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1000)
		)
		let waiting = ConversationTurnTiming(
			turnID: "waiting",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 2000)
		)
		let duplicateWaiting = ConversationTurnTiming(
			turnID: "waiting",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 3000)
		)
		let rows = ConversationTranscriptRow.make(
			entries: entries,
			timings: clocks + [empty, waiting, duplicateWaiting, ConversationTurnTiming(
				turnID: "unstarted",
				status: "inProgress"
			), ConversationTurnTiming(
				turnID: "historical",
				status: "completed",
				durationMs: 4000
			)],
			projectPath: "/project"
		)
		#expect(rows.map(\.id) == [
			"user:request",
			"timing:user",
			"timing:command",
			"activity-group:command:first",
			"timing:image",
			"image:item",
			"missing:notice",
			"timing:plain",
			"plain",
			"timing:empty",
			"timing:waiting",
			"timing:waiting"
		])
		let timings = rows.compactMap
		{
			row -> ConversationTurnTiming? in
			guard case .turnStatus(let timing) = row
			else
			{
				return nil
			}
			return timing
		}
		#expect(timings == [clocks[2],
							clocks[1],
							clocks[0],
							clocks[3],
							empty,
							waiting,
							duplicateWaiting])
	}

	@Test func historyPrependsAndReplyUpdatesKeepTimingOrderAndRowIdentities()
	{
		let request = messageEntry(
			"latest:request",
			kind: .user
		)
		var reply = messageEntry("latest:reply")
		let liveTiming = ConversationTurnTiming(
			turnID: "latest",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1000)
		)
		let current = ConversationTranscriptRow.make(
			entries: [request, reply],
			timings: [liveTiming],
			projectPath: nil
		)
		var historyEntries: [ConversationEntry] = []
		var historyTimings: [ConversationTurnTiming] = []
		var expectedHistory: [ConversationTranscriptRow] = []
		for index in 0 ..< 1000
		{
			let user = messageEntry(
				"history-\(index):request",
				kind: .user
			)
			let agent = messageEntry("history-\(index):reply")
			let timing = ConversationTurnTiming(
				turnID: "history-\(index)",
				status: "completed",
				durationMs: Double(index + 1)
			)
			historyEntries.append(contentsOf: [user, agent])
			historyTimings.append(timing)
			expectedHistory.append(contentsOf: [
				.message(user),
				.turnStatus(timing),
				.message(agent)
			])
		}
		let timings = [liveTiming] + Array(historyTimings.reversed())
		let loaded = ConversationTranscriptRow.make(
			entries: historyEntries + [request, reply],
			timings: timings,
			projectPath: nil
		)
		#expect(loaded == expectedHistory + current)
		reply.body = "The streamed reply grew."
		let updated = ConversationTranscriptRow.make(
			entries: historyEntries + [request, reply],
			timings: timings,
			projectPath: nil
		)
		#expect(updated.map(\.id) == loaded.map(\.id))
		#expect(updated == expectedHistory + [
			.message(request),
			.turnStatus(liveTiming),
			.message(reply)
		])
	}

	private func messageEntry(
		_ id: String,
		kind: ConversationEntryKind = .agent
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "Message",
			body: "Body"
		)
	}

	private func commandEntry(
		_ id: String,
		actions: [CodexCommandAction]
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(ConversationCommand(
				command: "original shell",
				cwd: "/tmp/work",
				output: "",
				status: "completed",
				exitCode: 0,
				durationMs: nil,
				actions: actions
			))
		)
	}
}
