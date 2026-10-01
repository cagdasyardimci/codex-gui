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
}
