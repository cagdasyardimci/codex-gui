import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationContentCacheTests
{

	@Test(arguments: [false, true])
	func richImageCostsEvictCachedMessagesBeforeTheEntryLimit(inlineMath: Bool) async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		func source(index: Int) -> String
		{
			if inlineMath
			{
				let latex = #"\frac{"# + String(
					repeating: "x+",
					count: 24
				) + "\(index + 1)}{"
					+ String(
						repeating: "y+",
						count: 24
					) + "1}"
				return Array(
					repeating: #"\("# + latex + #"\)"#,
					count: 4
				)
				.joined(separator: " ") + "\n\nMessage \(index)"
			}
			let diagram = "```mermaid\nflowchart LR\n"
				+ "A[Independent message \(index)] --> B[Cache pressure]\n```"
			return Array(
				repeating: diagram,
				count: 8
			).joined(separator: "\n\n")
		}
		let firstSource = inlineMath ? source(index: -1)
			: "```mermaid\nflowchart LR\nA[First cached source] --> B[Result]\n```"
		let first = await cache.content(
			body: firstSource,
			markdown: true,
			prepareDiagrams: !inlineMath
		)
		try #require(first.estimatedRichImageBytes > 0)
		#expect(await cache.content(
			body: firstSource,
			markdown: true,
			prepareDiagrams: !inlineMath
		) === first)
		let capacity = 6 * 1024 * 1024
		var aggregateCost = firstSource.utf8.count + first.estimatedRichImageBytes
		var sourceBytes = firstSource.utf8.count
		var latestSource = firstSource
		var latest = first
		for index in 0 ..< 32
		{
			latestSource = source(index: index)
			latest = await cache.content(
				body: latestSource,
				markdown: true,
				prepareDiagrams: !inlineMath
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
			markdown: true,
			prepareDiagrams: !inlineMath
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
