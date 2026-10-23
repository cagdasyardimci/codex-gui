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
		let cache = MarkdownRichBlockImageCache()
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
		let cache = MarkdownRichBlockImageCache(capacity: 2)
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
		let bounded = MarkdownRichBlockImageCache(
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
		let disabled = MarkdownRichBlockImageCache(capacity: 0)
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
		let first = PreparedConversationContent(MarkdownContentParser.parse(
			source + "\n\nFirst streamed tail",
			markdown: true
		))
		var budget = MarkdownRichBlockBudget()
		let images = try #require(MarkdownRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget
		))
		let next = PreparedConversationContent(MarkdownContentParser.parse(
			source + "\n\nUpdated streamed tail",
			markdown: true
		))
		budget = MarkdownRichBlockBudget()
		let repeated = try #require(MarkdownRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget
		))
		#expect(images.light === repeated.light)
		#expect(images.dark === repeated.dark)
		#expect((images.light.representations.first?.pixelsWide ?? 0) ==
			Int(images.lightSize.width * 2))
		let firstAttachment = try attachment(in: first)
		let nextAttachment = try attachment(in: next)
		#expect(firstAttachment !== nextAttachment)
		#expect(firstAttachment.attachmentCell !== nextAttachment.attachmentCell)
		#expect(firstAttachment.source.utf8.elementsEqual(source.utf8))
		#expect(nextAttachment.source.utf8.elementsEqual(source.utf8))
		#expect(next.attributedString.string.hasSuffix("Updated streamed tail"))
		let lightBytes = try #require(raster(images.light)?.dataProvider?.data) as Data
		let darkBytes = try #require(raster(images.dark)?.dataProvider?.data) as Data
		#expect(lightBytes != darkBytes)
	}

	@Test func cacheHitsConsumeEveryMessagePixelAndBlockBudget() throws
	{
		_ = NSApplication.shared
		let latex = #"\frac{17}{19}"#
		var initialBudget = MarkdownRichBlockBudget()
		let images = try #require(MarkdownRichBlockRenderer.mathImages(
			latex: latex,
			budget: &initialBudget
		))
		var budget = MarkdownRichBlockBudget(
			maximumPixels: images.budgetPixelCost,
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
		var exhaustedBlocks = MarkdownRichBlockBudget(maximumBlocks: 0)
		#expect(try !richMath(
			latex,
			budget: &exhaustedBlocks
		).rendersNativeImage)
		var freshBudget = MarkdownRichBlockBudget()
		#expect(try richMath(
			latex,
			budget: &freshBudget
		).rendersNativeImage)

		let diagram = try fixtureImages()
		var diagramBudget = MarkdownRichBlockBudget(
			maximumPixels: diagram.budgetPixelCost,
			maximumBlocks: 2
		)
		#expect((MarkdownRichBlockRenderer.diagramAttachment(
			source: "diagram",
			budget: &diagramBudget,
			preparedImages: diagram
		) as? MarkdownRichAttachment)?.rendersNativeImage == true)
		#expect((MarkdownRichBlockRenderer.diagramAttachment(
			source: "diagram",
			budget: &diagramBudget,
			preparedImages: diagram
		) as? MarkdownRichAttachment)?.rendersNativeImage == false)
		var noDiagramBlocks = MarkdownRichBlockBudget(maximumBlocks: 0)
		#expect((MarkdownRichBlockRenderer.diagramAttachment(
			source: "diagram",
			budget: &noDiagramBlocks,
			preparedImages: diagram
		) as? MarkdownRichAttachment)?.rendersNativeImage == false)
	}

	@Test func displaySizesDoNotChangeRetainedRasterCosts() throws
	{
		let original = try fixtureImages()
		let size = NSSize(
			width: 1.25,
			height: 0.75
		)
		let images = MarkdownRichBlockImageCache.Images(
			light: try #require(raster(original.light)),
			dark: try #require(raster(original.dark)),
			lightSize: size,
			darkSize: size
		)
		let cache = MarkdownRichBlockImageCache()
		let cacheKey = key("fractional")
		cache.insert(
			images,
			for: cacheKey
		)
		let cached = try #require(cache.images(for: cacheKey))
		#expect(cached.pixelCount == original.pixelCount)
		#expect(cached.attachment(source: "fractional").estimatedRichImageBytes == cached.byteCount)
		#expect(cached.byteCount == original.byteCount)
		#expect(cached.budgetPixelCost * 4 >= cached.byteCount)
		var budget = MarkdownRichBlockBudget(maximumPixels: cached.budgetPixelCost)
		let firstReservation = budget.reservePixels(cached.budgetPixelCost)
		let secondReservation = budget.reservePixels(cached.budgetPixelCost)
		#expect(firstReservation)
		#expect(!secondReservation)
	}

	@Test func inlineMathChargesActualRasterBytesAndFallbacksCostNothing() throws
	{
		_ = NSApplication.shared
		let latex = #"\frac{17}{19}"#
		let content = PreparedConversationContent(MarkdownContentParser.parse(
			#"\("# + latex + #"\) and \(\definitelyUnknownCommand{x}\)"#,
			markdown: true
		))
		var attachments: [(NSRange, MarkdownInlineMathAttachment)] = []
		content.attributedString.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: content.attributedString.length
			)
		)
		{
			value, range, _ in
			if let attachment = value as? MarkdownInlineMathAttachment
			{
				attachments.append((range, attachment))
			}
		}
		try #require(attachments.count == 2)
		let font = try #require(content.attributedString.attribute(
			.font,
			at: attachments[0].0.location,
			effectiveRange: nil
		) as? NSFont)
		var budget = MarkdownRichBlockBudget()
		let images = try #require(MarkdownRichBlockRenderer.mathImages(
			latex: latex,
			budget: &budget,
			fontSize: font.pointSize,
			inline: true
		))
		let lightRaster = try #require(raster(images.light))
		let darkRaster = try #require(raster(images.dark))
		let actualBytes = lightRaster.bytesPerRow * lightRaster.height
			+ darkRaster.bytesPerRow * darkRaster.height
		#expect(attachments[0].1.rendersNativeImage)
		#expect(attachments[0].1.estimatedRichImageBytes == actualBytes)
		#expect(content.estimatedRichImageBytes == actualBytes)
		#expect(!attachments[1].1.rendersNativeImage)
		#expect(attachments[1].1.estimatedRichImageBytes == 0)
		var exhaustedBudget = MarkdownRichBlockBudget(maximumPixels: 0)
		let rejected = MarkdownInlineMathAttachment(
			latex: latex,
			source: #"\("# + latex + #"\)"#,
			font: font,
			budget: &exhaustedBudget
		)
		#expect(!rejected.rendersNativeImage)
		#expect(rejected.estimatedRichImageBytes == 0)
	}

	private func key(
		_ source: String,
		kind: MarkdownRichBlockImageCache.Key.Kind = .diagram,
		parameters: [CGFloat] = [2]
	) -> MarkdownRichBlockImageCache.Key
	{
		MarkdownRichBlockImageCache.Key(
			kind: kind,
			payload: Data(source.utf8),
			parameters: parameters
		)
	}

	private func fixtureImages(pixelDimension: Int = 4) throws -> MarkdownRichBlockImageCache
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
		return MarkdownRichBlockImageCache.Images(
			light: image,
			dark: image,
			lightSize: size,
			darkSize: size
		)
	}

	private func attachment(in content: PreparedConversationContent) throws
		-> MarkdownRichAttachment
	{
		let text = content.attributedString
		let range = (text.string as NSString).range(of: "\u{FFFC}")
		try #require(range.location != NSNotFound)
		return try #require(text.attribute(
			.attachment,
			at: range.location,
			effectiveRange: nil
		) as? MarkdownRichAttachment)
	}

	private func richMath(
		_ latex: String,
		budget: inout MarkdownRichBlockBudget
	) throws -> MarkdownRichAttachment
	{
		try #require(MarkdownRichBlockRenderer.mathAttachment(
			latex: latex,
			source: "$$" + latex + "$$",
			budget: &budget
		) as? MarkdownRichAttachment)
	}
	private func raster(_ image: NSImage) -> CGImage?
	{
		image.cgImage(
			forProposedRect: nil,
			context: nil,
			hints: nil
		)
	}

}
