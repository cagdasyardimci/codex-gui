import Foundation

/// Prepares text independently of view layout and discards superseded render requests.
@MainActor
final class TranscriptPreparationCoordinator
{
	struct ContentKey: Equatable
	{
		let body: String
		let markdown: Bool
		let preserveSoftBreaks: Bool

		init(
			body: String,
			markdown: Bool,
			preserveSoftBreaks: Bool = false
		)
		{
			self.body = body
			self.markdown = markdown
			self.preserveSoftBreaks = preserveSoftBreaks
		}

		static func make(
			for entry: ConversationEntry,
			expanded: Bool
		) -> Self?
		{
			// Commands and images use activity rows, without prepared message text.
			guard entry.activity == nil
			else
			{
				return nil
			}
			let collapsed = entry.isExpandable && !expanded
			let body = collapsed ? collapsedPreview(of: entry.body) : entry.body
			return Self(
				body: body,
				markdown: entry.kind == .agent || entry.kind == .user,
				preserveSoftBreaks: entry.kind == .user
			)
		}

		static func collapsedPreview(of body: String) -> String
		{
			var preview = ""
			var separators = 0
			for scalar in body.unicodeScalars
			{
				if CharacterSet.newlines.contains(scalar)
				{
					if separators == 1
					{
						return preview
					}
					separators += 1
					preview += "\n"
				}
				else
				{
					preview.unicodeScalars.append(scalar)
				}
			}
			return preview
		}
	}

	private let contentCache = ConversationContentCache()
	private let navigationCache = ConversationTurnSummary.Cache()
	private(set) var turnSummaries: [ConversationTurnSummary] = []
	private var preparedContents: [String: PreparedConversationContent] = [:]
	private var preparedKeys: [String: ContentKey] = [:]
	private var preparationTask: Task<Void, Never>?
	private var renderGeneration = 0

	func waitForRendering() async
	{
		await preparationTask?.value
	}

	func prepare(
		_ nextEntries: [ConversationEntry],
		keys: [ContentKey?],
		context: String? = nil,
		onPrepared: @escaping ([String: PreparedConversationContent]) -> Void
	)
	{
		preparationTask?.cancel()
		renderGeneration += 1
		let generation = renderGeneration
		let existingContents = preparedContents
		let existingKeys = preparedKeys
		preparationTask = Task
		{
			[weak self, contentCache, navigationCache] in
			var contents: [String: PreparedConversationContent] = [:]
			for (entry, key) in zip(
				nextEntries,
				keys
			)
			{
				guard !Task.isCancelled
				else
				{
					return
				}
				guard let key
				else
				{
					continue
				}
				if existingKeys[entry.id] == key, let prepared = existingContents[entry.id]
				{
					contents[entry.id] = prepared
				}
				else
				{
					contents[entry.id] = await contentCache.content(
						body: key.body,
						markdown: key.markdown,
						preserveSoftBreaks: key.preserveSoftBreaks
					)
				}
			}
			guard let self, !Task.isCancelled, generation == self.renderGeneration
			else
			{
				return
			}
			let summaries = await navigationCache.make(
				from: ConversationTurnSummary.sources(from: nextEntries),
				context: context
			)
			guard let summaries, !Task.isCancelled, generation == self.renderGeneration
			else
			{
				return
			}
			self.preparedKeys = Dictionary(uniqueKeysWithValues: zip(
				nextEntries,
				keys
			).compactMap
			{
				entry, key in
				key.map
				{
					(entry.id, $0)
				}
			})
			self.preparedContents = contents
			self.turnSummaries = summaries
			onPrepared(contents)
		}
	}
}
