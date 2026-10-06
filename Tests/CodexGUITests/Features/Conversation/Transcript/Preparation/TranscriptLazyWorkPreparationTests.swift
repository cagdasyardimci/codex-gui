import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptLazyWorkPreparationTests
{
	@Test func foldedWorkSkipsPreparationAndJumpRevealsItsLatestContent() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var entries = [
			entry(
				"turn:request",
				kind: .user,
				body: "Request"
			),
			entry(
				"turn:comment",
				kind: .agent,
				body: "Old commentary"
			),
			entry(
				"turn:legacy",
				kind: .command,
				body: "first\nsecond\nthird"
			),
			entry(
				"turn:tool",
				kind: .tool,
				body: "Tool text"
			),
			entry(
				"turn:reply",
				kind: .agent,
				body: "```swift\nlet final = true\n```"
			),
		]
		let presentation = snapshot(entries)
		controller.render(presentation)
		await controller.waitForRendering()
		let visibleIDs: Set<String> = [entries[0].id, entries[4].id]
		#expect(Set(controller.preparedContents.keys) == visibleIDs)
		#expect(controller.transcriptPreparation.contentPreparationRequestCount == 2)
		let reply = try #require(controller.preparedContents[entries[4].id])
		#expect(reply.codeBlocks == ["let final = true\n"])
		#expect(controller.replyActionEntryID == entries[4].id)

		entries[1].body = "Latest **commentary**"
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		#expect(Set(controller.preparedContents.keys) == visibleIDs)
		#expect(controller.transcriptPreparation.contentPreparationRequestCount == 2)
		#expect(controller.preparedContents[entries[4].id] === reply)

		controller.jumpToEntry(id: entries[1].id)
		await controller.waitForRendering()
		#expect(controller.expandedTurnIDs == ["turn"])
		#expect(controller.requestedJumpItemID == nil)
		#expect(Set(controller.preparedContents.keys) == Set(entries.map(\.id)))
		#expect(controller.transcriptPreparation.contentPreparationRequestCount == 5)
		#expect(controller.preparedContents[entries[1].id]?.attributedString.string
			== "Latest commentary")
		#expect(controller.preparedContents[entries[4].id] === reply)

		controller.toggleTurnWork("turn")
		await controller.waitForRendering()
		#expect(Set(controller.preparedContents.keys) == visibleIDs)
		#expect(controller.transcriptPreparation.contentPreparationRequestCount == 5)
		#expect(controller.replyActionEntryID == entries[4].id)
	}

	@Test func supersededOwnerCannotPublishRevealedWorkIntoACollapsedTranscript() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let entries = [
			entry(
				"turn:request",
				kind: .user,
				body: "Request"
			),
			entry(
				"turn:comment",
				kind: .agent,
				body: "**Work**"
			),
			entry(
				"turn:reply",
				kind: .agent,
				body: "Reply"
			),
		]
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		controller.toggleTurnWork("turn")
		controller.render(snapshot(
			entries,
			threadID: "other"
		))
		await controller.waitForRendering()
		#expect(controller.expandedTurnIDs.isEmpty)
		#expect(controller.preparedContents[entries[1].id] == nil)
		#expect(controller.displayedRows.map(\.id)
			== [entries[0].id, "timing:turn", entries[2].id])
		#expect(controller.replyActionEntryID == entries[2].id)

		var active = snapshot(
			entries,
			threadID: "other"
		)
		active.turnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "inProgress",
			startedAt: Date(timeIntervalSince1970: 1)
		)]
		controller.render(active)
		await controller.waitForRendering()
		#expect(controller.preparedContents[entries[1].id]?.attributedString.string == "Work")
		#expect(controller.displayedRows.contains
		{
			$0.id == entries[1].id
		})
	}

	private func entry(
		_ id: String,
		kind: ConversationEntryKind,
		body: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "Entry",
			body: body
		)
	}

	private func snapshot(
		_ entries: [ConversationEntry],
		threadID: String = "reading"
	) -> ConversationSnapshot
	{
		var result = ConversationSnapshot(
			projectPath: "/tmp/lazy-transcript",
			threads: [],
			selectedThreadID: threadID,
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		result.turnTimings = [ConversationTurnTiming(
			turnID: "turn",
			status: "completed",
			durationMs: 1000
		)]
		return result
	}
}
