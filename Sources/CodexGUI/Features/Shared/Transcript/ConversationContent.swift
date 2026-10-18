import AppKit

/// Immutable text prepared for one displayed version of a conversation entry.
final class PreparedConversationContent: @unchecked Sendable
{
	let attributedString: NSAttributedString
	let codeBlocks: [String]
	let codeBlockRanges: [NSRange]
	let estimatedRichImageBytes: Int
	private struct SizeKey: Hashable
	{
		let width: CGFloat
		let expandable: Bool
		let presentation: Int
	}
	@MainActor private var measuredSizes: [SizeKey: NSSize] = [:]
	@MainActor private var measuredOrder: [SizeKey] = []
	@MainActor private var displayTexts: [Int: NSAttributedString] = [:]
	@MainActor private var naturalWidths: [Int: CGFloat] = [:]
	@MainActor private var bodyHeights: [SizeKey: CGFloat] = [:]
	@MainActor private var bodyHeightOrder: [SizeKey] = []

	@MainActor
	init(
		_ parsed: ParsedMarkdownContent,
		imageThumbnails: [String: SourceThumbnailLoader.Thumbnail] = [:]
	)
	{
		attributedString = MarkdownAttributedStringRenderer.render(
			parsed.runs,
			imageThumbnails: imageThumbnails
		)
		codeBlocks = parsed.codeBlocks
		codeBlockRanges = parsed.codeBlockRanges
		estimatedRichImageBytes = Self.richImageBytes(in: attributedString)
	}

	@MainActor
	private static func richImageBytes(in text: NSAttributedString) -> Int
	{
		var attachments: Set<ObjectIdentifier> = []
		var bytes = 0
		text.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: text.length
			),
			options: []
		)
		{
			value, _, _ in
			guard let attachment = value as? NSTextAttachment,
					attachments.insert(ObjectIdentifier(attachment)).inserted
			else
			{
				return
			}
			bytes += (attachment as? MarkdownRichAttachment)?.estimatedRichImageBytes
				?? (attachment as? MarkdownImageGalleryAttachment)?.estimatedRichImageBytes ?? 0
		}
		return bytes
	}

	@MainActor
	func cachedSize(
		width: CGFloat,
		expandable: Bool,
		presentation: Int = 0,
		calculate: () -> NSSize
	) -> NSSize
	{
		let key = SizeKey(
			width: width,
			expandable: expandable,
			presentation: presentation
		)
		if let size = measuredSizes[key]
		{
			return size
		}
		let size = calculate()
		measuredSizes[key] = size
		measuredOrder.append(key)
		if measuredOrder.count > 32
		{
			measuredSizes.removeValue(forKey: measuredOrder.removeFirst())
		}
		return size
	}

	@MainActor
	func cachedDisplayText(
		presentation: Int,
		calculate: () -> NSAttributedString
	)
		-> NSAttributedString
	{
		if let text = displayTexts[presentation]
		{
			return text
		}
		let text = NSAttributedString(attributedString: calculate())
		if displayTexts.count < 5
		{
			displayTexts[presentation] = text
		}
		return text
	}

	@MainActor
	func cachedNaturalWidth(
		presentation: Int,
		calculate: () -> CGFloat
	) -> CGFloat
	{
		if let width = naturalWidths[presentation]
		{
			return width
		}
		let width = calculate()
		if naturalWidths.count < 5
		{
			naturalWidths[presentation] = width
		}
		return width
	}

	@MainActor
	func cachedBodyHeight(
		width: CGFloat,
		presentation: Int,
		calculate: () -> CGFloat
	) -> CGFloat
	{
		let key = SizeKey(
			width: width,
			expandable: false,
			presentation: presentation
		)
		if let height = bodyHeights[key]
		{
			return height
		}
		let height = calculate()
		bodyHeights[key] = height
		bodyHeightOrder.append(key)
		if bodyHeightOrder.count > 32
		{
			bodyHeights.removeValue(forKey: bodyHeightOrder.removeFirst())
		}
		return height
	}

}

actor ConversationContentCache
{
	private struct Key: Hashable
	{
		let body: Data
		let markdown: Bool
		let preserveSoftBreaks: Bool
	}

	private var values: [Key: PreparedConversationContent] = [:]
	private var insertionOrder: [Key] = []
	private var storedCosts: [Key: Int] = [:]
	private var storedBytes = 0
	private let capacity = 64
	private let byteCapacity = 6 * 1024 * 1024

	func content(
		body: String,
		markdown: Bool,
		preserveSoftBreaks: Bool = false
	) async -> PreparedConversationContent
	{
		let key = Key(
			body: Data(body.utf8),
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
