import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationRichBlockImageCacheTests
{
	@Test func exactPayloadKindAndRenderingParametersSeparateCacheEntries() throws
	{
		let composed = "Caf\u{E9}"
		let decomposed = "Cafe\u{0301}"
		#expect(composed == decomposed)
		let cache = ConversationRichBlockImageCache()
		let images = try fixtureImages()
		let original = key(composed)
		cache.insert(
			images,
			for: original
		)
		#expect(cache.images(for: original)?.light === images.light)
		#expect(cache.images(for: key(decomposed)) == nil)
		#expect(cache.images(for: key(
			composed,
			kind: .math
		)) == nil)
		#expect(cache.images(for: key(
			composed,
			parameters: [1]
		)) == nil)
	}

	@Test func entryAndByteBoundsEvictUnusedPairsWithoutRetainingOversizedImages() throws
	{
		let images = try fixtureImages()
		let cache = ConversationRichBlockImageCache(capacity: 2)
		cache.insert(
			images,
			for: key("first")
		)
		cache.insert(
			images,
			for: key("active")
		)
		#expect(cache.images(for: key("first")) != nil)
		cache.insert(
			images,
			for: key("new")
		)
		#expect(cache.images(for: key("first")) != nil)
		#expect(cache.images(for: key("active")) == nil)

		let bytes = images.byteCount + 1 + 8 + 128
		let bounded = ConversationRichBlockImageCache(
			capacity: 32,
			byteCapacity: bytes
		)
		bounded.insert(
			images,
			for: key("a")
		)
		bounded.insert(
			images,
			for: key("b")
		)
		#expect(bounded.images(for: key("a")) == nil)
		#expect(bounded.images(for: key("b")) != nil)
		bounded.insert(
			try fixtureImages(pixelDimension: 16),
			for: key("large")
		)
		#expect(bounded.images(for: key("large")) == nil)
		#expect(bounded.images(for: key("b")) != nil)
		let disabled = ConversationRichBlockImageCache(capacity: 0)
		disabled.insert(
			images,
			for: key("disabled")
		)
		#expect(disabled.images(for: key("disabled")) == nil)
	}

	@Test func changedMessageBodiesReuseImagesWithFreshSourceBackedAttachments() throws
	{
		_ = NSApplication.shared
		let latex = #"\int_0^1 x^2\,dx = \frac{1}{3}"#
		let source = "$$\n" + latex + "\n$$"
		let first = PreparedConversationContent(ConversationContentParser.parse(
			source + "\n\nFirst streamed tail",
			markdown: true
		))
		var budget = ConversationRichBlockBudget()
		let images = try #require(ConversationRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget
		))
		let next = PreparedConversationContent(ConversationContentParser.parse(
			source + "\n\nUpdated streamed tail",
			markdown: true
		))
		budget = ConversationRichBlockBudget()
		let repeated = try #require(ConversationRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget
		))
		#expect(images.light === repeated.light)
		#expect(images.dark === repeated.dark)
		#expect(images.light.width == Int(images.lightSize.width * 2))
		let firstAttachment = try attachment(in: first)
		let nextAttachment = try attachment(in: next)
		#expect(firstAttachment !== nextAttachment)
		#expect(firstAttachment.attachmentCell !== nextAttachment.attachmentCell)
		#expect(firstAttachment.source.utf8.elementsEqual(source.utf8))
		#expect(nextAttachment.source.utf8.elementsEqual(source.utf8))
		#expect(next.attributedString.string.hasSuffix("Updated streamed tail"))
		let lightBytes = try #require(images.light.dataProvider?.data) as Data
		let darkBytes = try #require(images.dark.dataProvider?.data) as Data
		#expect(lightBytes != darkBytes)
	}

	@Test func diagramPayloadBytesAreExactAndCellsKeepTheirCurrentSource() throws
	{
		_ = NSApplication.shared
		let composed = "flowchart LR\nA[Caf\u{E9}] --> B[Done]"
		let decomposed = "flowchart LR\nA[Cafe\u{0301}] --> B[Done]"
		var budget = ConversationRichBlockBudget()
		let first = try #require(ConversationRichBlockRenderer.diagramImages(
			code: composed,
			budget: &budget
		))
		budget = ConversationRichBlockBudget()
		let second = try #require(ConversationRichBlockRenderer.diagramImages(
			code: decomposed,
			budget: &budget
		))
		#expect(first.light !== second.light)
		budget = ConversationRichBlockBudget()
		let repeated = try #require(ConversationRichBlockRenderer.diagramImages(
			code: composed,
			budget: &budget
		))
		#expect(first.light === repeated.light)
		let one = first.attachment(source: "```mermaid\n" + composed + "\n```")
		let two = repeated.attachment(source: "~~~mermaid\n" + composed + "\n~~~")
		#expect(one !== two)
		#expect(one.attachmentCell !== two.attachmentCell)
		#expect(two.source.hasPrefix("~~~mermaid"))
	}

	@Test func cacheHitsConsumeEveryMessagePixelAndBlockBudget() throws
	{
		_ = NSApplication.shared
		let latex = #"\frac{17}{19}"#
		var initialBudget = ConversationRichBlockBudget()
		let images = try #require(ConversationRichBlockRenderer.mathImages(
			latex: latex,
			budget: &initialBudget
		))
		var budget = ConversationRichBlockBudget(
			maximumPixels: images.pixelCount,
			maximumBlocks: 2
		)
		let first = try richMath(
			latex,
			budget: &budget
		)
		let rejected = try richMath(
			latex,
			budget: &budget
		)
		#expect(first.rendersNativeImage)
		#expect(!rejected.rendersNativeImage)
		#expect(rejected.source == "$$" + latex + "$$")
		var exhaustedBlocks = ConversationRichBlockBudget(maximumBlocks: 0)
		#expect(try !richMath(
			latex,
			budget: &exhaustedBlocks
		).rendersNativeImage)
		var freshBudget = ConversationRichBlockBudget()
		#expect(try richMath(
			latex,
			budget: &freshBudget
		).rendersNativeImage)

		let code = "flowchart LR\nA[Cached budget] --> B[Result]"
		var warmBudget = ConversationRichBlockBudget()
		let diagram = try #require(ConversationRichBlockRenderer.diagramImages(
			code: code,
			budget: &warmBudget
		))
		var diagramBudget = ConversationRichBlockBudget(
			maximumPixels: diagram.pixelCount,
			maximumBlocks: 2
		)
		#expect(ConversationRichBlockRenderer.diagramImages(
			code: code,
			budget: &diagramBudget
		) != nil)
		#expect(ConversationRichBlockRenderer.diagramImages(
			code: code,
			budget: &diagramBudget
		) == nil)
		var noDiagramBlocks = ConversationRichBlockBudget(maximumBlocks: 0)
		#expect(ConversationRichBlockRenderer.diagramImages(
			code: code,
			budget: &noDiagramBlocks
		) == nil)
	}

	@Test func fractionalSizesSharePixelEstimatesButRetainActualRowByteAccounting() throws
	{
		let original = try fixtureImages()
		let size = NSSize(
			width: 1.25,
			height: 0.75
		)
		let images = ConversationRichBlockImageCache.Images(
			light: original.light,
			dark: original.dark,
			lightSize: size,
			darkSize: size
		)
		let cache = ConversationRichBlockImageCache()
		let cacheKey = key("fractional")
		cache.insert(
			images,
			for: cacheKey
		)
		let cached = try #require(cache.images(for: cacheKey))
		// Each image rounds up to 3 by 2 pixels at scale 2.
		#expect(cached.pixelCount == 12)
		#expect(cached.attachment(source: "fractional").estimatedRichImageBytes == 48)
		#expect(cached.byteCount == original.light.bytesPerRow * original.light.height
			+ original.dark.bytesPerRow * original.dark.height)
		var budget = ConversationRichBlockBudget(maximumPixels: 12)
		let firstReservation = budget.reservePixels(cached.pixelCount)
		let secondReservation = budget.reservePixels(cached.pixelCount)
		#expect(firstReservation)
		#expect(!secondReservation)
	}

	@Test func aRejectedBudgetDoesNotMemoizeRenderingFailure() throws
	{
		_ = NSApplication.shared
		let code = "flowchart LR\nA[" + UUID().uuidString + "] --> B[Result]"
		var rejectedBudget = ConversationRichBlockBudget(maximumPixels: 0)
		#expect(ConversationRichBlockRenderer
			.diagramImages(
				code: code,
				budget: &rejectedBudget
			) == nil)
		var freshBudget = ConversationRichBlockBudget()
		#expect(ConversationRichBlockRenderer
			.diagramImages(
				code: code,
				budget: &freshBudget
			) != nil)
	}

	private func key(
		_ source: String,
		kind: ConversationRichBlockImageCache.Key.Kind = .diagram,
		parameters: [CGFloat] = [2]
	) -> ConversationRichBlockImageCache.Key
	{
		ConversationRichBlockImageCache.Key(
			kind: kind,
			payload: Data(source.utf8),
			parameters: parameters
		)
	}

	private func fixtureImages(pixelDimension: Int = 4) throws -> ConversationRichBlockImageCache
		.Images
	{
		let context = try #require(CGContext(
			data: nil,
			width: pixelDimension,
			height: pixelDimension,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		let image = try #require(context.makeImage())
		let size = NSSize(
			width: CGFloat(pixelDimension) / 2,
			height: CGFloat(pixelDimension) / 2
		)
		return ConversationRichBlockImageCache.Images(
			light: image,
			dark: image,
			lightSize: size,
			darkSize: size
		)
	}

	private func attachment(in content: PreparedConversationContent) throws
		-> ConversationRichAttachment
	{
		let text = content.attributedString
		let range = (text.string as NSString).range(of: "\u{FFFC}")
		try #require(range.location != NSNotFound)
		return try #require(text.attribute(
			.attachment,
			at: range.location,
			effectiveRange: nil
		) as? ConversationRichAttachment)
	}

	private func richMath(
		_ latex: String,
		budget: inout ConversationRichBlockBudget
	) throws -> ConversationRichAttachment
	{
		try #require(ConversationRichBlockRenderer.mathAttachment(
			latex: latex,
			source: "$$" + latex + "$$",
			budget: &budget
		) as? ConversationRichAttachment)
	}
}
