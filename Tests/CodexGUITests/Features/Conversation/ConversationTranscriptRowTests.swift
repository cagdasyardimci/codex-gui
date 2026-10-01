import Foundation
import Testing

@testable import CodexGUI

struct ConversationTranscriptRowTests
{
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
			projectPath: "/project"
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
			.group,
			.command
		])
		#expect(activities[0].title == "Read files, ran commands")
		#expect(activities[1].filePath == "/tmp/work/file")
		#expect(activities[1].sourceEntryID == activities[2].sourceEntryID)
		#expect(activities[1].id != activities[2].id)
		#expect(activities[4].expanded)
	}

	@Test func shellNamesDoNotOverrideUnknownMetadataAndExpansionDoesNotRequireOutput()
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
			Issue.record("Missing action"); return
		}
		#expect(action.kind == .command)
		#expect(action.title == "Ran original shell")
		#expect(action.expanded)
		#expect(action.command?.output == "")
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
			projectPath: nil,
			collapsedGroupIDs: ["activity-group:one:a"]
		)
		#expect(rows.count == 3)
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
			projectPath: nil,
			collapsedGroupIDs: ["activity-group:turn:item"]
		)
		guard case .activity(let group) = collapsed[0]
		else
		{
			return
		}
		#expect(group.title == "Read files, ran commands · 1 failed")
		#expect(collapsed.count == 1)
		let expanded = ConversationTranscriptRow.make(
			entries: [entry],
			projectPath: nil
		)
		guard case .activity(let action) = expanded.last
		else
		{
			return
		}
		#expect(action.title == "Ran python3 - script")
		#expect(action.command?.command == "python3  -\n  script")
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
