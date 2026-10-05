import Foundation

/// A local preview of a loaded turn. No generated summary or backend request is needed.
struct ConversationTurnSummary: Equatable, Sendable
{
	let turnID: String
	var entryID: String
	let title: String
	var reply: String
	var isContentLoaded = true
	var isPreviewLoaded = false
	var previewError: String?

	static func navigation(
		references: [ConversationTurnReference],
		loaded: [ConversationTurnSummary],
		cached: [ConversationTurnSummary] = [],
		errors: [String: String] = [:]
	) -> [Self]
	{
		let previews = Dictionary(
			loaded.map
			{
				($0.turnID, $0)
			},
			uniquingKeysWith:
			{
				first, _ in first
			}
		)
		let cachedPreviews = Dictionary(
			cached.map
			{
				($0.turnID, $0)
			},
			uniquingKeysWith:
			{
				first, _ in first
			}
		)
		let referenced = Set(references.map(\.id))
		return references.map
		{
			reference in
			if let loaded = previews[reference.id]
			{
				return loaded
			}
			if var preview = cachedPreviews[reference.id]
			{
				preview.entryID = reference.id + ":reference"
				preview.isContentLoaded = false
				preview.isPreviewLoaded = true
				return preview
			}
			return Self(
				turnID: reference.id,
				entryID: reference.id + ":reference",
				title: reference.startedAt.map
				{
					"Turn from " + $0.formatted(
						date: .abbreviated,
						time: .shortened
					)
				} ?? "Earlier turn",
				reply: "Select to view this turn.",
				isContentLoaded: false,
				previewError: errors[reference.id]
			)
		} + loaded.filter
		{
			!referenced.contains($0.turnID)
		}
	}

	static func make(from entries: [ConversationEntry]) -> [Self]
	{
		var previews = PreviewCache()
		return previews.make(from: sources(from: entries))
	}

	struct Source: Sendable
	{
		let turnID: String
		let entryID: String
		let title: String
		var replyBody: String?
	}

	static func sources(from entries: [ConversationEntry]) -> [Source]
	{
		var sources: [Source] = []
		var indices: [String: Int] = [:]
		for entry in entries
		{
			guard let separator = entry.id.firstIndex(of: ":")
			else
			{
				continue
			}
			let turnID = String(entry.id[..<separator])
			if entry.kind == .user, indices[turnID] == nil
			{
				indices[turnID] = sources.count
				sources.append(Source(
					turnID: turnID,
					entryID: entry.id,
					title: preview(entry.body),
					replyBody: nil
				))
			}
			else if entry.kind == .agent, let index = indices[turnID]
			{
				// Earlier commentary is replaced by the last reply in the loaded turn.
				sources[index].replyBody = entry.body
			}
		}
		return sources
	}

	struct PreviewCache
	{
		private struct Reply
		{
			let prefix: Data
			let text: String
		}

		private var replies: [String: Reply] = [:]
		private let capacity: Int
		private let byteCapacity: Int

		init(
			capacity: Int = 2_048,
			byteCapacity: Int = 2 * 1_024 * 1_024
		)
		{
			self.capacity = max(
				0,
				capacity
			)
			self.byteCapacity = max(
				0,
				byteCapacity
			)
		}

		mutating func make(
			from sources: [Source],
			renderReply: (String) -> String = ConversationTurnSummary.renderReply
		) -> [ConversationTurnSummary]
		{
			var summaries = sources.map
			{
				ConversationTurnSummary(
					turnID: $0.turnID,
					entryID: $0.entryID,
					title: $0.title,
					reply: ""
				)
			}
			var nextReplies: [String: Reply] = [:]
			var retainedBytes = 0
			// Keep recent turns when the loaded history exceeds the cache budget.
			for index in sources.indices.reversed()
			{
				let source = sources[index]
				guard let body = source.replyBody
				else
				{
					continue
				}
				let excerpt = String(body.prefix(400))
				let prefix = Data(excerpt.utf8)
				let reply: Reply
				if let cached = replies[source.turnID], cached.prefix == prefix
				{
					reply = cached
				}
				else
				{
					reply = Reply(
						prefix: prefix,
						text: renderReply(excerpt)
					)
				}
				summaries[index].reply = reply.text
				let byteCount = prefix.count + reply.text.utf8.count + source.turnID.utf8.count + 96
				if nextReplies.count < capacity, byteCount <= byteCapacity - retainedBytes
				{
					nextReplies[source.turnID] = reply
					retainedBytes += byteCount
				}
			}
			replies = nextReplies
			return summaries
		}
	}

	actor Cache
	{
		private var context: String?
		private var previews = PreviewCache()
		private let renderReply: @Sendable (String) -> String

		init(
			renderReply: @escaping @Sendable (String) -> String =
			{
				ConversationTurnSummary.renderReply($0)
			}
		)
		{
			self.renderReply = renderReply
		}

		func make(
			from sources: [Source],
			context: String?
		) -> [ConversationTurnSummary]?
		{
			guard !Task.isCancelled
			else
			{
				return nil
			}
			var nextPreviews = self.context == context ? previews : PreviewCache()
			let summaries = nextPreviews.make(
				from: sources,
				renderReply: renderReply
			)
			guard !Task.isCancelled
			else
			{
				return nil
			}
			self.context = context
			previews = nextPreviews
			return summaries
		}
	}

	private static func renderReply(_ excerpt: String) -> String
	{
		let parsed = ConversationContentParser.parse(
			excerpt,
			markdown: true
		)
		return ConversationPlainTextRenderer.render(parsed)
	}

	private static func preview(_ text: String) -> String
	{
		let prefix = String(text.prefix(400))
		return prefix.split(whereSeparator:
			{
				$0.isWhitespace
			}).joined(separator: " ")
	}
}
