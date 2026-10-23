import AppKit
import PDFKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct MarkdownMermaidRendererTests
{
	@Test func mathAndDiagramBenchmarkKeepsLateDiagramsRenderedAtReadableNaturalSizes() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let parsed = MarkdownContentParser.parse(
				MarkdownMermaidFixtures.previewDocument,
				markdown: true
			)
			var diagnostics: [String] = []
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			{
				diagnostics.append($0.description)
			}
			try #require(
				images.count == 11,
				Comment(rawValue: diagnostics.joined(separator: "; "))
			)
			let content = MarkdownAttributedStringRenderer.render(
				parsed.runs,
				preparedDiagramImages: images,
				richBlockMaximumPixels: MarkdownMermaidRenderer.maximumPreparedPixels,
				mathFontSize: FileMarkdownStyling.mathFontSize
			)
			var diagramCount = 0
			content.enumerateAttribute(
				.attachment,
				in: NSRange(
					location: 0,
					length: content.length
				)
			)
			{
				value, _, _ in
				guard let attachment = value as? MarkdownRichAttachment,
						attachment.source.hasPrefix("```mermaid")
				else
				{
					return
				}
				diagramCount += 1
				#expect(
					attachment.rendersNativeImage,
					Comment(rawValue: String(attachment.source.prefix(50)))
				)
			}
			#expect(diagramCount == 11)
			let diagrams = parsed.runs.compactMap(\.style.richBlock).filter
			{
				$0.kind == .diagram
			}
			for block in diagrams
			{
				let pair = try #require(images[Data(block.payload.utf8)])
				#expect(pair.lightSize.width <= 1_800 && pair.lightSize.height <= 1_800)
				#expect(pair.pixelCount == 0)
				if block.payload.hasPrefix("mindmap")
				{
					#expect(pair.lightSize.width >= 300 && pair.lightSize.height >= 200)
					#expect(pair.lightSize.width > pair.lightSize.height * 2)
				}
				if block.payload.hasPrefix("gantt")
				{
					#expect(abs(pair.lightSize.width - 1_512) < 1)
				}
			}
		}
	}

	@Test func benchmarkDiagramFamiliesProduceBothBoundedAppearances() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let sources = MarkdownMermaidFixtures.diagrams.map
			{
				$0 + "\n"
			}
			let parsed = MarkdownContentParser.parse(
				sources.map
				{
					"```mermaid\n" + $0 + "```"
				}.joined(separator: "\n\n"),
				markdown: true
			)
			var diagnostics: [String] = []
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			{
				diagnostics.append($0.description)
			}
			#expect(sources.count == 11)
			#expect(
				images.count == sources.count,
				Comment(rawValue: diagnostics.joined(separator: "; "))
			)
			#expect(images.values.reduce(0)
			{
				$0 + $1.budgetPixelCost
			}
			<= MarkdownMermaidRenderer.maximumPreparedPixels)
			var budget = MarkdownRichBlockBudget(
				maximumPixels: MarkdownMermaidRenderer.maximumPreparedPixels
			)
			for code in sources
			{
				let pair = try #require(
					images[Data(code.utf8)],
					Comment(rawValue: String(code.prefix(40)))
				)
				for image in [pair.light, pair.dark]
				{
					let vector = try #require(image as? MarkdownSVGImage)
					#expect(vector.size.width > 1 && vector.size.height > 1)
					#expect(!vector.representations.isEmpty)
					#expect(vector.representations.allSatisfy
					{
						!($0 is NSBitmapImageRep)
					})
					let markup = try #require(String(
						data: vector.svgData,
						encoding: .utf8
					))
					#expect(markup.contains("<svg"))
					#expect(!markup.contains("data:image/png"))
				}
				let lightBytes = try #require((pair.light as? MarkdownSVGImage)?.svgData)
				let darkBytes = try #require((pair.dark as? MarkdownSVGImage)?.svgData)
				let lightPDF = try #require((pair.light as? MarkdownSVGImage)?.pdfData)
				let darkPDF = try #require((pair.dark as? MarkdownSVGImage)?.pdfData)
				#expect(pair.light.representations.first is NSPDFImageRep)
				#expect(pair.dark.representations.first is NSPDFImageRep)
				let document = try #require(PDFDocument(data: lightPDF))
				#expect(document.pageCount == 1)
				#expect(!(document.string ?? "").isEmpty)
				let copy = try #require(pair.light.copy() as? MarkdownSVGImage)
				#expect(copy.svgData == lightBytes && copy.pdfData == lightPDF)
				#expect(copy.cacheMode == .never)
				let lightRaster = try #require(pair.light.cgImage(
					forProposedRect: nil,
					context: nil,
					hints: nil
				))
				let darkRaster = try #require(pair.dark.cgImage(
					forProposedRect: nil,
					context: nil,
					hints: nil
				))
				let lightInk = try #require(lightRaster.dataProvider?.data) as Data
				let darkInk = try #require(darkRaster.dataProvider?.data) as Data
				#expect(lightInk.contains
				{
					$0 != 0
				})
				#expect(lightInk != darkInk)
				#expect(pair.byteCount == lightBytes.count + darkBytes.count
					+ lightPDF.count + darkPDF.count)
				#expect(lightBytes != darkBytes)
				let source = "```mermaid\n" + code + "```"
				let attachment = try #require(MarkdownRichBlockRenderer.diagramAttachment(
					source: source,
					budget: &budget,
					preparedImages: pair
				) as? MarkdownRichAttachment)
				#expect(attachment.rendersNativeImage)
				#expect(attachment.source == source)
			}
		}
	}

	@Test func classLayoutAndExportKeepReferenceVectorTextMetrics() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let source = try #require(MarkdownMermaidFixtures.diagrams.first
			{
				$0.hasPrefix("classDiagram")
			})
			let parsed = MarkdownContentParser.parse(
				"```mermaid\n" + source + "\n```",
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			let pair = try #require(images.values.first)
			for image in [pair.light, pair.dark]
			{
				let vector = try #require(image as? MarkdownSVGImage)
				// Screen-scaled WebKit text used to narrow this benchmark to 179.0625 pt.
				#expect(abs(vector.size.width - 187.4375) < 0.5)
				#expect(abs(vector.size.height - 521) < 0.5)
				let pdf = try #require(vector.pdfData)
				let document = try #require(PDFDocument(data: pdf))
				let page = try #require(document.page(at: 0))
				let label = try #require(document.findString(
					"contains",
					withOptions: []
				).first)
				#expect(abs(label.bounds(for: page).width - 54.84375) < 0.5)
				#expect(abs(label.bounds(for: page).midX - vector.size.width / 2) < 0.5)
				let exported = try #require(MarkdownDiagramExport.file(vector))
				#expect(exported.data == vector.svgData)
				let markup = try #require(String(
					data: exported.data,
					encoding: .utf8
				))
				let rootTag = String(markup.prefix(while:
					{
						$0 != ">"
					})).lowercased()
				#expect(rootTag.contains("text-rendering:") && rootTag
					.contains("geometricprecision"))
				#expect(!markup.contains("data:image/png"))
				#expect(vector.representations.allSatisfy
				{
					!($0 is NSBitmapImageRep)
				})
			}
		}
	}

	@Test func defaultFlowchartRectanglesUseReferencePaddingWithoutChangingSemanticShapes(
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			for (node, width, height) in [
				("A[API]", 111.0, 76.0),
				("A[(Database)]", 94.85, 76.51)
			]
			{
				let parsed = MarkdownContentParser.parse(
					"```mermaid\nflowchart LR\n" + node + "\n```",
					markdown: true
				)
				let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
				let pair = try #require(images.values.first)
				for image in [pair.light, pair.dark]
				{
					// Each natural canvas includes Mermaid's eight-point padding around its node.
					#expect(abs(image.size.width - width) < 0.5)
					#expect(abs(image.size.height - height) < 0.5)
					#expect(image.representations.allSatisfy
					{
						!($0 is NSBitmapImageRep)
					})
				}
			}
		}
	}

	@Test func groupedFlowchartMeasuresResponsePillBeforeLayingOutItsSubgraphs() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let source = try #require(MarkdownMermaidFixtures.diagrams.first
			{
				$0.hasPrefix("flowchart LR") && $0.contains("subgraph Client")
			})
			let parsed = MarkdownContentParser.parse(
				"```mermaid\n" + source + "\n```",
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			let pair = try #require(images.values.first)
			for image in [pair.light, pair.dark]
			{
				let vector = try #require(image as? MarkdownSVGImage)
				#expect(abs(vector.size.width - 805.094) < 0.5)
				#expect(abs(vector.size.height - 169.511) < 0.5)
				let pdf = try #require(vector.pdfData)
				let document = try #require(PDFDocument(data: pdf))
				let page = try #require(document.page(at: 0))
				let label = try #require(document.findString(
					"Response",
					withOptions: []
				).first)
				#expect(abs(label.bounds(for: page).width - 59.2578) < 0.5)
			}
		}
	}

	@Test(arguments: [false, true])
	func classAndStateRelationshipLabelsRetainBlueBacking(isState: Bool) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let diagram = isState
				? "stateDiagram-v2\nIdle --> Complete: related\n"
				: "classDiagram\nDocument --> Block: related\n"
			let parsed = MarkdownContentParser.parse(
				"```mermaid\n" + diagram + "```",
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			let pair = try #require(images.values.first)
			let image = try #require(pair.light as? MarkdownSVGImage)
			let pdf = try #require(image.pdfData)
			let document = try #require(PDFDocument(data: pdf))
			let page = try #require(document.page(at: 0))
			let selection = try #require(document.findString(
				"related",
				withOptions: []
			).first)
			let labelBounds = selection.bounds(for: page)
			let raster = try #require(image.cgImage(
				forProposedRect: nil,
				context: nil,
				hints: nil
			))
			let bitmap = NSBitmapImageRep(cgImage: raster)
			let pageBounds = page.bounds(for: .mediaBox)
			let scaleX = CGFloat(bitmap.pixelsWide) / pageBounds.width
			let scaleY = CGFloat(bitmap.pixelsHigh) / pageBounds.height
			let left = max(
				0,
				Int(floor(labelBounds.minX * scaleX))
			)
			let right = min(
				bitmap.pixelsWide,
				Int(ceil(labelBounds.maxX * scaleX))
			)
			let top = max(
				0,
				Int(floor((pageBounds.maxY - labelBounds.maxY) * scaleY))
			)
			let bottom = min(
				bitmap.pixelsHigh,
				Int(ceil((pageBounds.maxY - labelBounds.minY) * scaleY))
			)
			try #require(left < right && top < bottom)
			var blueBackingPixels = 0
			for y in top ..< bottom
			{
				for x in left ..< right
				{
					guard let color = bitmap.colorAt(
						x: x,
						y: y
					)?.usingColorSpace(.deviceRGB)
					else
					{
						continue
					}
					if color.alphaComponent > 0.15 && color.blueComponent - color
						.redComponent > 0.03
						&& color.blueComponent - color.greenComponent > 0.015
					{
						blueBackingPixels += 1
					}
				}
			}
			#expect(blueBackingPixels > 4)
		}
	}

	@Test func entityRelationshipLabelsRemainReadableBetweenTheEntities() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let source = "```mermaid\n" + MarkdownMermaidFixtures.diagrams[7] + "\n```"
			let parsed = MarkdownContentParser.parse(
				source,
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			let pair = try #require(images.values.first)
			let cgImage = try #require(pair.light.cgImage(
				forProposedRect: nil,
				context: nil,
				hints: nil
			))
			let bitmap = NSBitmapImageRep(cgImage: cgImage)
			// The first relationship sits between USER and CHAT, outside both entity boxes.
			// A solid blue label background used to hide all of the label's dark text.
			var ink = 0
			for y in (bitmap.pixelsHigh * 24 / 100) ..< (bitmap.pixelsHigh * 30 / 100)
			{
				for x in 0 ..< bitmap.pixelsWide
				{
					guard let color = bitmap.colorAt(
						x: x,
						y: y
					)?.usingColorSpace(.deviceRGB)
					else
					{
						continue
					}
					if color.alphaComponent > 0.8 && color.redComponent < 0.3
						&& color.greenComponent < 0.3 && color.blueComponent < 0.3
					{
						ink += 1
					}
				}
			}
			#expect(ink > 12)
		}
	}

	@Test func invalidSyntaxAndOversizedInputKeepExactSourceFallback() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let source = "```mermaid\nflowchart LR\nA[Missing bracket --> B[Result]\n```"
			let parsed = MarkdownContentParser.parse(
				source,
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			#expect(images.isEmpty)
			let block = try #require(parsed.runs.compactMap(\.style.richBlock).first)
			var budget = MarkdownRichBlockBudget()
			let attachment = try #require(MarkdownRichBlockRenderer.diagramAttachment(
				source: block.source,
				budget: &budget,
				preparedImages: images[Data(block.payload.utf8)]
			) as? MarkdownRichAttachment)
			#expect(!attachment.rendersNativeImage)
			#expect(attachment.source == source)
			#expect(!MarkdownMermaidRenderer.admits(String(
				repeating: "x",
				count: 8_193
			)))
			#expect(!MarkdownMermaidRenderer.admits("flowchart LR\nA-->B\u{2028}C-->D"))
		}
	}

	@Test func cancelledPreparationReleasesItsQueueSlot() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let parsed = MarkdownContentParser.parse(
				"```mermaid\nsequenceDiagram\nAlice->>Bob: Hello\n```",
				markdown: true
			)
			let cancelled = Task
			{
				await MarkdownMermaidRenderer.prepare(parsed: parsed)
			}
			cancelled.cancel()
			#expect(await cancelled.value.isEmpty)
			let subsequent = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			#expect(subsequent.count == 1)
		}
	}

	@Test func canonicallyEquivalentSourcesKeepExactUTF8PreparationKeys() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let composed = "flowchart LR\nA[Caf\u{E9}] --> B[Result]\n"
			let decomposed = "flowchart LR\nA[Cafe\u{0301}] --> B[Result]\n"
			#expect(composed == decomposed)
			let parsed = MarkdownContentParser.parse(
				"```mermaid\n" + composed + "```\n\n```mermaid\n" + decomposed + "```",
				markdown: true
			)
			let images = await MarkdownMermaidRenderer.prepare(parsed: parsed)
			#expect(images.count == 2)
			#expect(images[Data(composed.utf8)] != nil)
			#expect(images[Data(decomposed.utf8)] != nil)
		}
	}
}
