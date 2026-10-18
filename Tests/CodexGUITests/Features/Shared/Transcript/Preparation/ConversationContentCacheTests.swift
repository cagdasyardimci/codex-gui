import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationContentCacheTests
{
	@Test func equivalentUnicodeCodeRetainsExactSourceRangesAndCopyBytes() async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		let item = ConversationCollectionItem()
		let pasteboard = NSPasteboard.withUniqueName()
		defer
		{
			pasteboard.releaseGlobally()
		}
		var previous: PreparedConversationContent?
		for scalarText in ["\u{00E9}", "e\u{0301}"]
		{
			let code = "let value = \"\(scalarText)\"\n"
			let body = "Predecessor \(scalarText)\n\n```swift\n\(code)```"
			let content = await cache.content(
				body: body,
				markdown: true
			)
			#expect(content !== previous)
			let range = try #require(content.codeBlockRanges.first)
			#expect(range.length == code.utf16.count)
			#expect(content.codeBlocks.first?.utf8.elementsEqual(code.utf8) == true)
			#expect((content.attributedString.string as NSString).substring(with: range)
				.utf8.elementsEqual(code.utf8))
			let entry = ConversationEntry(
				id: "turn:reply",
				kind: .agent,
				title: "Codex",
				body: body
			)
			item.configure(
				entry,
				content: content,
				expanded: false,
				showsReplyActions: true,
				onToggle:
				{
				}
			)
			let codeButton = try #require(descendants(item.view).compactMap
			{
				$0 as? NSButton
			}
			.first
			{
				$0.accessibilityLabel() == "Copy code block 1"
			})
			item.writeCodeBlock(
				from: codeButton,
				to: pasteboard
			)
			#expect(pasteboard.string(forType: .string)?.utf8.elementsEqual(code.utf8) == true)
			let reply = try #require(descendants(item.view).compactMap
			{
				$0 as? ConversationReplyActionsView
			}.first)
			reply.writeResponse(to: pasteboard)
			#expect(pasteboard.string(forType: .string)?.utf8.elementsEqual(body.utf8) == true)
			previous = content
		}
	}

	@Test func richImageCostsEvictCachedMessagesBeforeTheEntryLimit() async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		let firstSource = "```mermaid\nflowchart LR\nA[First cached source] --> B[Result]\n```"
		let first = await cache.content(
			body: firstSource,
			markdown: true
		)
		try #require(first.estimatedRichImageBytes > 0)
		#expect(await cache.content(
			body: firstSource,
			markdown: true
		) === first)
		let capacity = 6 * 1024 * 1024
		var aggregateCost = firstSource.utf8.count + first.estimatedRichImageBytes
		var sourceBytes = firstSource.utf8.count
		var latestSource = firstSource
		var latest = first
		for index in 0 ..< 32
		{
			latestSource = "```mermaid\nflowchart LR\n"
				+ "A[Independent message \(index)] --> B[Cache pressure]\n```"
			latest = await cache.content(
				body: latestSource,
				markdown: true
			)
			try #require(latest.estimatedRichImageBytes > 0)
			aggregateCost += latestSource.utf8.count + latest.estimatedRichImageBytes
			sourceBytes += latestSource.utf8.count
			if aggregateCost > capacity
			{
				break
			}
		}
		try #require(aggregateCost > capacity)
		#expect(sourceBytes < capacity)
		#expect(await cache.content(
			body: latestSource,
			markdown: true
		) === latest)
		let reloadedFirst = await cache.content(
			body: firstSource,
			markdown: true
		)
		#expect(reloadedFirst !== first)
		#expect(reloadedFirst.codeBlocks == first.codeBlocks)
		#expect(reloadedFirst.attributedString.string == first.attributedString.string)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
