import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct MarkdownSVGImageTests
{
	@Test func copiesAndAttachmentsKeepUncachedVectorRepresentationsAndExportableSource() throws
	{
		let image = try vector(fill: "#5796ff")
		let copied = try #require(image.copy() as? MarkdownSVGImage)
		#expect(copied !== image)
		#expect(copied.svgData == image.svgData)
		#expect(copied.size == image.size)
		for candidate in [image, copied]
		{
			#expect(candidate.cacheMode == .never)
			#expect(!candidate.representations.isEmpty)
			#expect(candidate.representations.allSatisfy
			{
				!($0 is NSBitmapImageRep)
			})
		}
		let pair = MarkdownRichBlockImageCache.Images(
			light: image,
			dark: image
		)
		let attachment = pair.attachment(
			source: "first source",
			isDiagram: true
		)
		let otherAttachment = pair.attachment(
			source: "second source",
			isDiagram: true
		)
		let appearance = try #require(NSAppearance(named: .aqua))
		let attached = try #require(attachment.diagramImage(for: appearance) as? MarkdownSVGImage)
		let other = try #require(otherAttachment.diagramImage(for: appearance) as? MarkdownSVGImage)
		#expect(attached !== image)
		#expect(attached !== other)
		#expect(attached.svgData == image.svgData)
		#expect(attached.accessibilityDescription == "first source")
		#expect(other.accessibilityDescription == "second source")
		#expect(image.accessibilityDescription == nil)
	}

	@Test func attachmentSelectionAndExportPreserveBothAppearancePayloads() throws
	{
		let light = try vector(fill: "#deecff")
		let dark = try vector(fill: "#1f3554")
		let pair = MarkdownRichBlockImageCache.Images(
			light: light,
			dark: dark
		)
		let attachment = pair.attachment(
			source: "diagram",
			isDiagram: true
		)
		for (appearanceName, expected) in [
			(NSAppearance.Name.aqua, light.svgData),
			(NSAppearance.Name.darkAqua, dark.svgData),
		]
		{
			let appearance = try #require(NSAppearance(named: appearanceName))
			let selected = try #require(attachment.diagramImage(for: appearance))
			let exported = try #require(MarkdownDiagramExport.file(selected))
			#expect(exported.data == expected)
			#expect(exported.contentType.identifier == "public.svg-image")
			#expect(exported.name == "diagram.svg")
		}
	}

	@Test func vectorByteCostsBoundCacheRetentionAndEveryAttachmentOccurrence() throws
	{
		let light = try vector(fill: "#deecff")
		let dark = try vector(
			fill: "#1f3554",
			padding: "x"
		)
		let pair = MarkdownRichBlockImageCache.Images(
			light: light,
			dark: dark
		)
		let retainedBytes = light.svgData.count + dark.svgData.count
		#expect(pair.pixelCount == 0)
		#expect(pair.byteCount == retainedBytes)
		#expect(pair.budgetPixelCost == (retainedBytes + 3) / 4)
		let firstKey = key("a")
		let secondKey = key("b")
		let entryBytes = retainedBytes + firstKey.payload.count + 128
		let exactCache = MarkdownRichBlockImageCache(
			capacity: 2,
			byteCapacity: entryBytes
		)
		exactCache.insert(
			pair,
			for: firstKey
		)
		#expect(exactCache.images(for: firstKey) != nil)
		exactCache.insert(
			pair,
			for: secondKey
		)
		#expect(exactCache.images(for: firstKey) == nil)
		#expect(exactCache.images(for: secondKey) != nil)
		let larger = try vector(
			fill: "#deecff",
			padding: String(
				repeating: "x",
				count: 256
			)
		)
		exactCache.insert(
			MarkdownRichBlockImageCache.Images(
				light: larger,
				dark: larger
			),
			for: firstKey
		)
		#expect(exactCache.images(for: firstKey) == nil)
		#expect(exactCache.images(for: secondKey) != nil)
		let undersizedCache = MarkdownRichBlockImageCache(byteCapacity: entryBytes - 1)
		undersizedCache.insert(
			pair,
			for: firstKey
		)
		#expect(undersizedCache.images(for: firstKey) == nil)

		var budget = MarkdownRichBlockBudget(
			maximumPixels: pair.budgetPixelCost,
			maximumBlocks: 2
		)
		let source = "```mermaid\nflowchart LR\nA-->B\n```"
		let accepted = try #require(MarkdownRichBlockRenderer.diagramAttachment(
			source: source,
			budget: &budget,
			preparedImages: pair
		) as? MarkdownRichAttachment)
		let rejected = try #require(MarkdownRichBlockRenderer.diagramAttachment(
			source: source,
			budget: &budget,
			preparedImages: pair
		) as? MarkdownRichAttachment)
		#expect(accepted.rendersNativeImage)
		#expect(accepted.estimatedRichImageBytes == retainedBytes)
		#expect(!rejected.rendersNativeImage)
		#expect(rejected.estimatedRichImageBytes == 0)
		#expect(rejected.source == source)
	}

	private func vector(
		fill: String,
		padding: String = ""
	) throws -> MarkdownSVGImage
	{
		let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"220\" height=\"500\">"
			+ "<rect width=\"220\" height=\"500\" fill=\"" + fill + "\"/>"
			+ "<!--" + padding + "--></svg>"
		return try #require(MarkdownSVGImage(
			data: Data(markup.utf8),
			size: NSSize(
				width: 220,
				height: 500
			)
		))
	}

	private func key(_ source: String) -> MarkdownRichBlockImageCache.Key
	{
		MarkdownRichBlockImageCache.Key(
			kind: .diagram,
			payload: Data(source.utf8),
			parameters: []
		)
	}
}
