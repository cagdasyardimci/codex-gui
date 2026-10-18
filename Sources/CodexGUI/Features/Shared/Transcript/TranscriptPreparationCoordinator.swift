import Foundation

/// Prepares text independently of view layout and discards superseded render requests.
@MainActor
final class TranscriptPreparationCoordinator
{
	typealias ContentKey = ConversationContentKey

	typealias ContentPreparation = @MainActor (ContentKey) async -> PreparedConversationContent

	private let prepareContent: ContentPreparation
	private let navigationCache = ConversationTurnSummary.Cache()
	private let netChangePreparation: ConversationNetFileChangePreparation
	private(set) var turnSummaries: [ConversationTurnSummary] = []
	private(set) var preparedNetChanges: [String: ConversationNetFileChangePreparation.Prepared] =
		[:]
	private(set) var contentPreparationRequestCount = 0
	private var preparedContents: [String: PreparedConversationContent] = [:]
	private var preparedKeys: [String: ContentKey] = [:]
	private(set) var preparationTask: Task<Void, Never>?
	private var renderGeneration = 0

	init(
		netChangePreparation: ConversationNetFileChangePreparation =
			ConversationNetFileChangePreparation(),
		prepareContent: ContentPreparation? = nil
	)
	{
		self.netChangePreparation = netChangePreparation
		let contentCache = ConversationContentCache()
		self.prepareContent = prepareContent ??
		{
			await contentCache.content(
				body: $0.body,
				markdown: $0.markdown,
				preserveSoftBreaks: $0.preserveSoftBreaks
			)
		}
	}

	func waitForRendering() async
	{
		await preparationTask?.value
	}

	func prepare(
		_ nextEntries: [ConversationEntry],
		keys: [ContentKey?],
		context: String? = nil,
		projectPath: String? = nil,
		onPrepared: @escaping ([String: PreparedConversationContent]) -> Void
	)
	{
		preparationTask?.cancel()
		renderGeneration += 1
		let generation = renderGeneration
		let existingContents = preparedContents
		let existingKeys = preparedKeys
		let changeSources = Self.fileChangeSources(
			from: nextEntries,
			repositoryRoot: projectPath
		)
		preparationTask = Task
		{
			[weak self, prepareContent, navigationCache, netChangePreparation] in
			async let netChanges = netChangePreparation.prepare(
				changeSources,
				context: context
			)
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
					self?.contentPreparationRequestCount += 1
					contents[entry.id] = await prepareContent(key)
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
			let changes = await netChanges
			guard let summaries, let changes, !Task.isCancelled,
					generation == self.renderGeneration
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
			self.preparedNetChanges = changes
			onPrepared(contents)
		}
	}

	static func fileChangeSources(
		from entries: [ConversationEntry],
		repositoryRoot: String? = nil
	) -> [ConversationNetFileChangePreparation.Source]
	{
		var turnIDs: [String] = []
		var changesByTurn: [String: [FileChange]] = [:]
		for entry in entries
		{
			guard case .fileChanges(
				let changes,
				let status
			) = entry.activity,
				status == "completed"
			else
			{
				continue
			}
			let turnID = ConversationEntryIdentity.turnIDWithFallback(entry.id)
			if changesByTurn[turnID] == nil
			{
				turnIDs.append(turnID)
			}
			changesByTurn[turnID, default: []]
				.append(contentsOf: ReportedRepositoryFileChanges.filter(
					changes,
					repositoryRoot: repositoryRoot
				))
		}
		return turnIDs.map
		{
			ConversationNetFileChangePreparation.Source(
				turnID: $0,
				changes: changesByTurn[$0] ?? []
			)
		}
	}
}
