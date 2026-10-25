import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptLazyWorkPreparationTests
{
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
