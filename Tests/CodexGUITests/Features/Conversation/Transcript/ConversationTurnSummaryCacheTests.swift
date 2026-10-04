import Foundation
import Testing

@testable import CodexGUI

@Suite
struct ConversationTurnSummaryCacheTests
{
	@Test func historicalPrefixesAreReusedUntilTheVisibleReplyPrefixChanges()
	{
		var entries = turns([
			"**First** reply",
			"**Second** reply",
			String(
				repeating: "😀",
				count: 400
			) + " streamed suffix",
		])
		var cache = ConversationTurnSummary.PreviewCache()
		var renders = 0
		let renderReply =
		{
			(body: String) in
			renders += 1
			return render(body)
		}
		let first = cache.make(
			from: ConversationTurnSummary.sources(from: entries),
			renderReply: renderReply
		)
		#expect(renders == 3)
		#expect(first[0].reply == "First reply")

		entries[entries.count - 1].body += " more streamed text"
		let samePrefix = cache.make(
			from: ConversationTurnSummary.sources(from: entries),
			renderReply: renderReply
		)
		#expect(samePrefix == first)
		#expect(renders == 3)

		entries[entries.count - 1].body = "Changed " + entries[entries.count - 1].body
		let changedPrefix = cache.make(
			from: ConversationTurnSummary.sources(from: entries),
			renderReply: renderReply
		)
		#expect(changedPrefix[0] == first[0])
		#expect(changedPrefix[1] == first[1])
		#expect(changedPrefix[2].reply.hasPrefix("Changed "))
		#expect(renders == 4)
	}

	@Test func onlyTheLastMatchingReplyIsParsedAndPrependedHistoryKeepsItsOrder()
	{
		let entries = [
			entry(
				"orphan:reply",
				.agent,
				"No request"
			),
			entry(
				"unqualified",
				.user,
				"No turn separator"
			),
			entry(
				"first:request",
				.user,
				"First\n request"
			),
			entry(
				"first:commentary",
				.agent,
				"Discarded commentary"
			),
			entry(
				"first:final",
				.agent,
				"**Final** reply"
			),
			entry(
				"first:steer",
				.user,
				"Later user entry"
			),
			entry(
				"second:request",
				.user,
				"Second request"
			),
			entry(
				"second:reply",
				.agent,
				"Second reply"
			),
		]
		var cache = ConversationTurnSummary.PreviewCache()
		var renderedBodies: [String] = []
		let renderReply =
		{
			(body: String) in
			renderedBodies.append(body)
			return render(body)
		}
		let first = cache.make(
			from: ConversationTurnSummary.sources(from: entries),
			renderReply: renderReply
		)
		#expect(first.map(\.turnID) == ["first", "second"])
		#expect(first[0].entryID == "first:request")
		#expect(first[0].title == "First request")
		#expect(first[0].reply == "Final reply")
		#expect(renderedBodies.count == 2)
		#expect(!renderedBodies.contains("Discarded commentary"))
		#expect(first == ConversationTurnSummary.make(from: entries))

		let earlier = [
			entry(
				"earlier:request",
				.user,
				"Earlier request"
			),
			entry(
				"earlier:reply",
				.agent,
				"Earlier reply"
			),
		] + entries
		let prepended = cache.make(
			from: ConversationTurnSummary.sources(from: earlier),
			renderReply: renderReply
		)
		#expect(prepended.map(\.turnID) == ["earlier", "first", "second"])
		#expect(Array(prepended.dropFirst()) == first)
		#expect(renderedBodies.count == 3)
	}

	@Test func canonicallyEquivalentPrefixesKeepTheirExactUtf8Bytes()
	{
		let composed = "**é**"
		let decomposed = "**e\u{0301}**"
		#expect(composed == decomposed)
		var cache = ConversationTurnSummary.PreviewCache()
		var renders = 0
		let renderReply =
		{
			(body: String) in
			renders += 1
			return render(body)
		}
		let first = cache.make(
			from: ConversationTurnSummary.sources(from: turns([composed])),
			renderReply: renderReply
		)
		let second = cache.make(
			from: ConversationTurnSummary.sources(from: turns([decomposed])),
			renderReply: renderReply
		)
		#expect(renders == 2)
		#expect(first[0].reply.utf8.elementsEqual("é".utf8))
		#expect(second[0].reply.utf8.elementsEqual("e\u{0301}".utf8))
	}

	@Test func retiredTurnsAndRemovedRepliesArePruned()
	{
		let sources = ConversationTurnSummary.sources(from: turns(["First", "Second"]))
		var cache = ConversationTurnSummary.PreviewCache()
		var renders = 0
		let renderReply =
		{
			(body: String) in
			renders += 1
			return render(body)
		}
		_ = cache.make(
			from: sources,
			renderReply: renderReply
		)
		_ = cache.make(
			from: [sources[1]],
			renderReply: renderReply
		)
		#expect(renders == 2)
		_ = cache.make(
			from: sources,
			renderReply: renderReply
		)
		#expect(renders == 3)

		var withoutReply = sources[0]
		withoutReply.replyBody = nil
		let removed = cache.make(
			from: [withoutReply, sources[1]],
			renderReply: renderReply
		)
		#expect(removed[0].reply.isEmpty)
		_ = cache.make(
			from: sources,
			renderReply: renderReply
		)
		#expect(renders == 4)
		#expect(cache.make(from: []).isEmpty)
		_ = cache.make(
			from: sources,
			renderReply: renderReply
		)
		#expect(renders == 6)
	}

	@Test func entryAndByteBudgetsRetainRecentTurnsAndRejectOversizedPrefixes()
	{
		let sources = ConversationTurnSummary.sources(from: turns(["First", "Second", "Third"]))
		var cache = ConversationTurnSummary.PreviewCache(capacity: 2)
		var renders = 0
		let renderReply =
		{
			(body: String) in
			renders += 1
			return render(body)
		}
		let first = cache.make(
			from: sources,
			renderReply: renderReply
		)
		let second = cache.make(
			from: sources,
			renderReply: renderReply
		)
		#expect(first == second)
		#expect(renders == 4)

		cache = ConversationTurnSummary.PreviewCache(byteCapacity: 200)
		renders = 0
		_ = cache.make(
			from: Array(sources.prefix(2)),
			renderReply: renderReply
		)
		_ = cache.make(
			from: Array(sources.prefix(2)),
			renderReply: renderReply
		)
		#expect(renders == 3)

		let longGrapheme = "a" + String(
			repeating: "\u{0301}",
			count: 150
		)
		#expect(longGrapheme.count == 1)
		let oversized = ConversationTurnSummary.sources(from: turns([longGrapheme]))
		renders = 0
		_ = cache.make(
			from: oversized,
			renderReply: renderReply
		)
		_ = cache.make(
			from: oversized,
			renderReply: renderReply
		)
		#expect(renders == 2)
	}

	@Test func ownerChangesResetPreviewsAndCancelledWorkRetainsTheAcceptedOwner() async throws
	{
		let recorder = ReplyRenderRecorder()
		let cache = ConversationTurnSummary.Cache
		{
			recorder.render($0)
		}
		let sources = ConversationTurnSummary.sources(from: turns(["Stable reply"]))
		let first = try #require(await cache.make(
			from: sources,
			context: "first-owner"
		))
		_ = await cache.make(
			from: sources,
			context: "first-owner"
		)
		#expect(recorder.count == 1)
		let next = try #require(await cache.make(
			from: sources,
			context: "second-owner"
		))
		#expect(next == first)
		#expect(recorder.count == 2)

		let cancelledSources = ConversationTurnSummary.sources(from: turns(["Cancel preview"]))
		let cancelled = Task
		{
			await cache.make(
				from: cancelledSources,
				context: "cancelled-owner"
			)
		}
		#expect(await cancelled.value == nil)
		#expect(recorder.count == 3)
		_ = await cache.make(
			from: sources,
			context: "second-owner"
		)
		#expect(recorder.count == 3)
		_ = await cache.make(
			from: sources,
			context: "first-owner"
		)
		#expect(recorder.count == 4)
	}

	private func turns(_ replies: [String]) -> [ConversationEntry]
	{
		replies.enumerated().flatMap
		{
			index, body in
			[
				entry(
					"\(index):request",
					.user,
					"Request \(index)"
				),
				entry(
					"\(index):reply",
					.agent,
					body
				),
			]
		}
	}

	private func entry(
		_ id: String,
		_ kind: ConversationEntryKind,
		_ body: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "",
			body: body
		)
	}

	private func render(_ body: String) -> String
	{
		ConversationPlainTextRenderer.render(ConversationContentParser.parse(
			body,
			markdown: true
		))
	}

	private final class ReplyRenderRecorder: @unchecked Sendable
	{
		private let lock = NSLock()
		private var calls = 0

		var count: Int
		{
			lock.lock()
			defer
			{
				lock.unlock()
			}
			return calls
		}

		func render(_ body: String) -> String
		{
			lock.lock()
			calls += 1
			lock.unlock()
			if body == "Cancel preview"
			{
				withUnsafeCurrentTask
				{
					$0?.cancel()
				}
			}
			return ConversationPlainTextRenderer.render(ConversationContentParser.parse(
				body,
				markdown: true
			))
		}
	}
}
