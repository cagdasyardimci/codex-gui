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
	}

	private let contentCache = ConversationContentCache()
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
		keys: [ContentKey],
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
			[weak self, contentCache] in
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
			self.preparedKeys = Dictionary(uniqueKeysWithValues: zip(
				nextEntries.map(\.id),
				keys
			))
			self.preparedContents = contents
			onPrepared(contents)
		}
	}
}
