import Foundation

/// Owns media preview requests for the current Sources inventory.
@MainActor
final class SourcePreviewCoordinator
{
	private struct Request
	{
		let token: UUID
		let task: Task<Void, Never>
	}

	private let loadThumbnail: @Sendable (String) async -> Data?
	private var currentRecords: [String: ConversationLocalSources.Record]
	private var requests: [String: Request] = [:]
	private var interruptedRecords = Set<String>()
	private var isInvalidated = false

	init(
		records: [ConversationLocalSources.Record],
		loadThumbnail: @escaping @Sendable (String) async -> Data?
	)
	{
		currentRecords = Self.index(records)
		self.loadThumbnail = loadThumbnail
	}

	isolated deinit
	{
		for request in requests.values
		{
			request.task.cancel()
		}
	}

	func update(
		records: [ConversationLocalSources.Record],
		renderedRecords: [String: ConversationLocalSources.Record]
	)
	{
		guard !isInvalidated
		else
		{
			return
		}
		currentRecords = Self.index(records)
		for id in Array(requests.keys) where renderedRecords[id] != currentRecords[id]
		{
			requests.removeValue(forKey: id)?.task.cancel()
			interruptedRecords.insert(id)
		}
	}

	func takeInterruptedRecords() -> Set<String>
	{
		let interrupted = interruptedRecords
		interruptedRecords.removeAll()
		return interrupted
	}

	func loadAudio(
		for record: ConversationLocalSources.Record,
		path: String,
		apply: @escaping @MainActor (String) -> Void
	)
	{
		let token = UUID()
		let task = Task
		{
			[weak self] in
			let duration = await SourceAudioMetadataLoader.duration(path: path)
			guard let self, self.accepts(
				record,
				token: token
			), let duration
			else
			{
				return
			}
			apply(duration)
		}
		register(
			task,
			for: record,
			token: token
		)
	}

	func loadImage(
		for record: ConversationLocalSources.Record,
		path: String,
		apply: @escaping @MainActor (Data?) -> Void
	)
	{
		let token = UUID()
		let loadThumbnail = loadThumbnail
		let task = Task
		{
			[weak self] in
			let data = await loadThumbnail(path)
			guard let self, self.accepts(
				record,
				token: token
			)
			else
			{
				return
			}
			apply(data)
		}
		register(
			task,
			for: record,
			token: token
		)
	}

	func invalidate()
	{
		isInvalidated = true
		for request in requests.values
		{
			request.task.cancel()
		}
		requests.removeAll()
		interruptedRecords.removeAll()
	}

	func tasks() -> [Task<Void, Never>]
	{
		requests.values.map(\.task)
	}

	private func register(
		_ task: Task<Void, Never>,
		for record: ConversationLocalSources.Record,
		token: UUID
	)
	{
		guard !isInvalidated, currentRecords[record.id] == record
		else
		{
			task.cancel()
			return
		}
		requests.removeValue(forKey: record.id)?.task.cancel()
		requests[record.id] = Request(
			token: token,
			task: task
		)
	}

	private func accepts(
		_ record: ConversationLocalSources.Record,
		token: UUID
	) -> Bool
	{
		!isInvalidated && !Task.isCancelled && currentRecords[record.id] == record
			&& requests[record.id]?.token == token
	}

	private static func index(
		_ records: [ConversationLocalSources.Record]
	) -> [String: ConversationLocalSources.Record]
	{
		Dictionary(
			records.map
			{
				($0.id, $0)
			},
			uniquingKeysWith:
			{
				_, latest in latest
			}
		)
	}
}
