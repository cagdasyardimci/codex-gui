import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TranscriptPreparationCoordinatorTests
{
	@Test func supersededPreparationCannotPublishAnOlderTranscript() async
	{
		let coordinator = TranscriptPreparationCoordinator()
		let entry = ConversationEntry(
			id: "entry",
			kind: .agent,
			title: "Answer",
			body: "old"
		)
		var publishedBodies: [String] = []
		for body in ["old", "latest"]
		{
			coordinator.prepare(
				[entry],
				keys: [TranscriptPreparationCoordinator.ContentKey(
					body: body,
					markdown: false
				)]
			)
			{
				contents in
				if let content = contents[entry.id]
				{
					publishedBodies.append(content.attributedString.string)
				}
			}
		}
		await coordinator.waitForRendering()
		#expect(publishedBodies == ["latest"])
	}

	@Test func unchangedEntryRetainsPreparedIdentityWhileStreamedBodyUpdates() async throws
	{
		let coordinator = TranscriptPreparationCoordinator()
		let entry = ConversationEntry(
			id: "entry",
			kind: .agent,
			title: "Answer",
			body: "first"
		)
		var published: [PreparedConversationContent] = []
		for body in ["first", "first", "streamed"]
		{
			coordinator.prepare(
				[entry],
				keys: [TranscriptPreparationCoordinator.ContentKey(
					body: body,
					markdown: false
				)]
			)
			{
				contents in
				if let content = contents[entry.id]
				{
					published.append(content)
				}
			}
			await coordinator.waitForRendering()
		}
		try #require(published.count == 3)
		#expect(published[0] === published[1])
		#expect(published[1] !== published[2])
		#expect(published[2].attributedString.string == "streamed")
	}

	@Test func supersededMarkdownStreamCannotPublishPartialCodeOrTableMetadata() async throws
	{
		let coordinator = TranscriptPreparationCoordinator()
		let entry = ConversationEntry(
			id: "stream",
			kind: .agent,
			title: "Answer",
			body: ""
		)
		let latest = "# Complete\n\n```swift\nlet latest = \"😀\"\n```"
		let bodies = [
			String(
				repeating: "old **streamed** paragraph\n\n",
				count: 500
			)
				+ "```swift\nlet obsolete =",
			"| Partial | Table |\n| --- | --- |\n| obsolete | cell |\n\n```text\npartial",
			latest,
		]
		var published: [PreparedConversationContent] = []
		for body in bodies
		{
			coordinator.prepare(
				[entry],
				keys: [TranscriptPreparationCoordinator.ContentKey(
					body: body,
					markdown: true
				)]
			)
			{
				contents in
				if let content = contents[entry.id]
				{
					published.append(content)
				}
			}
		}
		await coordinator.waitForRendering()
		try #require(published.count == 1)
		#expect(published[0].attributedString.string == "Complete\n\nlet latest = \"😀\"\n")
		#expect(published[0].codeBlocks == ["let latest = \"😀\"\n"])
		#expect(published[0].codeBlockRanges.count == 1)
	}

	@Test func structuredActivitiesSkipPreparationAndFallbackTextRemains() async throws
	{
		let coordinator = TranscriptPreparationCoordinator()
		let command = ConversationCommand(
			command: "swift test",
			cwd: nil,
			output: String(
				repeating: "hidden output\n",
				count: 10_000
			),
			status: "completed",
			exitCode: 0,
			durationMs: nil,
			actions: []
		)
		let entries = [
			ConversationEntry(
				id: "turn:request",
				kind: .user,
				title: "You",
				body: "first\nsecond"
			),
			ConversationEntry(
				id: "turn:command",
				kind: .command,
				title: "Command",
				body: command.output,
				isExpandable: true,
				activity: .command(command)
			),
			ConversationEntry(
				id: "turn:legacy-command",
				kind: .command,
				title: "Command",
				body: "$ legacy\r\nfirst output\nlast output",
				isExpandable: true
			),
			ConversationEntry(
				id: "turn:image",
				kind: .tool,
				title: "Image",
				body: "Structured image",
				activity: .image(path: "/tmp/preparation-test.png")
			),
			ConversationEntry(
				id: "turn:legacy-image",
				kind: .tool,
				title: "Image",
				body: "Fallback image text"
			),
			ConversationEntry(
				id: "turn:reply",
				kind: .agent,
				title: "Codex",
				body: "first\nsecond"
			),
		]
		let keys = entries.map
		{
			TranscriptPreparationCoordinator.ContentKey.make(
				for: $0,
				expanded: false
			)
		}
		#expect(keys[1] == nil)
		#expect(keys[3] == nil)
		var published: [String: PreparedConversationContent] = [:]
		coordinator.prepare(
			entries,
			keys: keys
		)
		{
			published = $0
		}
		await coordinator.waitForRendering()
		#expect(Set(published.keys) == Set([
			"turn:request",
			"turn:legacy-command",
			"turn:legacy-image",
			"turn:reply",
		]))
		#expect(published["turn:request"]?.attributedString.string == "first\nsecond")
		#expect(published["turn:legacy-command"]?.attributedString.string == "$ legacy\n")
		#expect(published["turn:legacy-image"]?.attributedString.string == "Fallback image text")
		#expect(published["turn:reply"]?.attributedString.string == "first second")
	}

	@Test func changingBetweenFallbackTextAndActivityPrunesUnusedPreparedEntries() async
	{
		let coordinator = TranscriptPreparationCoordinator()
		var entry = ConversationEntry(
			id: "turn:command",
			kind: .command,
			title: "Command",
			body: "output"
		)
		var publishedIDs: [[String]] = []
		for activity: ConversationActivity? in [nil, .image(path: "/tmp/image.png"), nil]
		{
			entry.activity = activity
			coordinator.prepare(
				[entry],
				keys: [TranscriptPreparationCoordinator.ContentKey.make(
					for: entry,
					expanded: false
				)]
			)
			{
				publishedIDs.append(Array($0.keys))
			}
			await coordinator.waitForRendering()
		}
		#expect(publishedIDs == [[entry.id], [], [entry.id]])
	}

}
