import Testing

@testable import CodexGUI

struct ConversationEntryEqualityTests
{
	@Test func literalMessageBytesInvalidateThePresentation()
	{
		let original = entry(body: "```\né\n```")
		var changed = original
		changed.body = "```\ne\u{301}\n```"
		#expect(original.body == changed.body)
		#expect(original != changed)
		#expect(original == original)
		changed = original
		changed.title = "e\u{301}"
		#expect(original.title == changed.title)
		#expect(original != changed)
	}

	@Test func activityOnlyChangesRetainExactCommandAndPatchBytes() throws
	{
		var original = entry(body: "")
		original.activity = .command(command(output: "é"))
		var changed = original
		changed.activity = .command(command(output: "e\u{301}"))
		#expect(original != changed)
		let first = try #require(FileChange(json: [
			"path": "file.swift",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-a\n+é"
		]))
		let second = try #require(FileChange(json: [
			"path": "file.swift",
			"kind": "update",
			"diff": "@@ -1 +1 @@\n-a\n+e\u{301}"
		]))
		#expect(first == second)
		original.activity = .fileChanges(
			[first],
			status: "completed"
		)
		changed = original
		changed.activity = .fileChanges(
			[second],
			status: "completed"
		)
		#expect(original != changed)
		changed.activity = .fileChanges(
			[first],
			status: "inProgress"
		)
		#expect(original != changed)
	}

	@Test func entryMetadataStillParticipatesInEquality() throws
	{
		let original = entry(body: "body")
		let reference = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/image.png"],
			id: "image"
		))
		let source = try #require(ConversationSourceActivity(json: [
			"id": "search",
			"type": "webSearch",
			"query": "source"
		]))
		let changes: [(inout ConversationEntry) -> Void] = [
			{
				$0.attachmentPreviewTitle = "attachment"
			},
			{
				$0.isExpandable = true
			},
			{
				$0.activity = .image(path: "/tmp/image.png")
			},
			{
				$0.imageAttachments = [reference]
			},
			{
				$0.sourceReferences = [reference]
			},
			{
				$0.sourceActivity = source
			},
		]
		for change in changes
		{
			var value = original
			change(&value)
			#expect(value != original)
		}
		#expect(original != entry(
			id: "other",
			body: "body"
		))
		#expect(original != entry(
			kind: .notice,
			body: "body"
		))
	}

	@Test func commandOwnerOutcomeTimingAndActionsStillParticipateInEquality()
	{
		let original = command(output: "output")
		for changed in [
			command(
				text: "other",
				output: "output"
			),
			command(
				cwd: "/other",
				output: "output"
			),
			command(
				output: "output",
				status: "failed"
			),
			command(
				output: "output",
				exitCode: 1
			),
			command(
				output: "output",
				durationMs: 2
			),
			command(
				output: "output",
				actions: [CodexCommandAction(
					kind: .read,
					command: "cat source"
				)]
			),
		]
		{
			#expect(original != changed)
		}
		#expect(original == command(output: "output"))
	}

	private func entry(
		id: String = "entry",
		kind: ConversationEntryKind = .agent,
		body: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "é",
			body: body
		)
	}

	private func command(
		text: String = "check",
		cwd: String = "/checkout",
		output: String,
		status: String = "completed",
		exitCode: Int = 0,
		durationMs: Double = 1,
		actions: [CodexCommandAction] = []
	) -> ConversationCommand
	{
		ConversationCommand(
			command: text,
			cwd: cwd,
			output: output,
			status: status,
			exitCode: exitCode,
			durationMs: durationMs,
			actions: actions
		)
	}
}
