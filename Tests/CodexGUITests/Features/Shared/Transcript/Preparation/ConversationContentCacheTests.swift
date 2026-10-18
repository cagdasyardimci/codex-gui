import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationContentCacheTests
{
	@Test func byteDifferentCodeRetainsItsOwnPreparedCopyText() async
	{
		let cache = ConversationContentCache()
		let composed = await cache.content(
			body: "```text\né\n```",
			markdown: true
		)
		let decomposed = await cache.content(
			body: "```text\ne\u{301}\n```",
			markdown: true
		)
		#expect(composed !== decomposed)
		#expect(composed.codeBlocks.first?.utf8.elementsEqual("é\n".utf8) == true)
		#expect(decomposed.codeBlocks.first?.utf8.elementsEqual("e\u{301}\n".utf8) == true)
		#expect(await cache.content(
			body: "```text\né\n```",
			markdown: true
		) === composed)
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

}
