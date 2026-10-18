import Foundation

actor ConversationContentCache
{

	private var values: [ConversationContentKey: PreparedConversationContent] = [:]
	private var insertionOrder: [ConversationContentKey] = []
	private var storedCosts: [ConversationContentKey: Int] = [:]
	private var storedBytes = 0
	private let capacity = 64
	private let byteCapacity = 6 * 1024 * 1024

	func content(
		body: String,
		markdown: Bool,
		preserveSoftBreaks: Bool = false
	) async -> PreparedConversationContent
	{
		let key = ConversationContentKey(
			body: body,
			markdown: markdown,
			preserveSoftBreaks: preserveSoftBreaks
		)
		if let cached = values[key]
		{
			return cached
		}

		let parsed = MarkdownContentParser.parse(
			body,
			markdown: markdown,
			preserveSoftBreaks: preserveSoftBreaks
		)
		let plan = MarkdownImagePreparation.preloadPlan(in: parsed.runs)
		var imageThumbnails: [String: SourceThumbnailLoader.Thumbnail] = [:]
		for path in plan.paths
		{
			guard !Task.isCancelled
			else
			{
				break
			}
			imageThumbnails[path] = await SourceThumbnailLoader.image(
				path: path,
				maximumPixelSize: plan.maximumPixelSize
			)
		}
		let prepared = await PreparedConversationContent(
			parsed,
			imageThumbnails: imageThumbnails
		)
		let byteCount = body.utf8.count + prepared.estimatedRichImageBytes
		if values[key] == nil && byteCount <= byteCapacity
		{
			values[key] = prepared
			storedCosts[key] = byteCount
			insertionOrder.append(key)
			storedBytes += byteCount
			while insertionOrder.count > capacity || storedBytes > byteCapacity
			{
				let oldest = insertionOrder.removeFirst()
				storedBytes -= storedCosts.removeValue(forKey: oldest) ?? 0
				values.removeValue(forKey: oldest)
			}
		}
		return prepared
	}
}
