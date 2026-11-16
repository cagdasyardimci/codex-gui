import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptLazyWorkPreparationTests
{
	@Test func settlingTheTurnColorsStreamedCodeWithoutChangingItsSource() async throws
	{
		let controller = ConversationViewController()
		let body = "```swift\nlet answer = 42\n```"
		let reply = entry(
			"turn:reply",
			kind: .agent,
			body: body
		)
		var running = snapshot(
			[reply],
			executionState: .running
		)
		running.activeThreadID = "reading"
		running.activeTurnID = "turn"
		controller.render(running)
		await controller.waitForRendering()
		let streamed = try #require(controller.transcript.preparedContents[reply.id])
		var stopped = snapshot(
			[reply],
			executionState: .stopped
		)
		stopped.activeThreadID = "reading"
		stopped.activeTurnID = "turn"
		controller.render(stopped)
		await controller.waitForRendering()
		let settled = try #require(controller.transcript.preparedContents[reply.id])
		#expect(settled !== streamed)
		#expect(settled.codeBlocks == streamed.codeBlocks)
		#expect(settled.attributedString.string == streamed.attributedString.string)
		#expect(settled.attributedString != streamed.attributedString)
	}

	@Test func sameEntryUnicodeCorrectionReachesBothTranscriptChangeDetectionGates() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		var previous: PreparedConversationContent?
		for scalarText in ["\u{00E9}", "e\u{0301}"]
		{
			let code = "let value = \"\(scalarText)\"\n"
			let body = "```swift\n\(code)```"
			let entries = [
				entry(
					"turn:request",
					kind: .user,
					body: "Request"
				),
				entry(
					"turn:reply",
					kind: .agent,
					body: body
				),
			]
			controller.render(snapshot(entries))
			await controller.waitForRendering()
			let prepared = try #require(controller.transcript.preparedContents["turn:reply"])
			#expect(prepared !== previous)
			#expect(prepared.codeBlocks.first?.utf8.elementsEqual(code.utf8) == true)
			#expect(prepared.codeBlockRanges.first?.length == code.utf16.count)
			#expect(controller.transcript.entries.last?.body.utf8.elementsEqual(body.utf8) == true)
			previous = prepared
		}
		#expect(controller.transcript.transcriptPreparation.contentPreparationRequestCount == 3)
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
		threadID: String = "reading",
		executionState: ExecutionState = .ready
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
			executionState: executionState,
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
