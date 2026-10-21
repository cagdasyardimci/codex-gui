import AppKit
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
				#expect(pair.lightSize.width <= 900 && pair.lightSize.height <= 1_800)
				#expect(pair.pixelCount == pair.light.width * pair.light.height
					+ pair.dark.width * pair.dark.height)
				if block.payload.hasPrefix("mindmap")
				{
					#expect(pair.lightSize.width >= 300 && pair.lightSize.height >= 200)
				}
				if block.payload.hasPrefix("gantt")
				{
					#expect(abs(pair.lightSize.width - 900) < 1)
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
					#expect(image.width > 1 && image.height > 1)
					#expect(image.width <= 4_096 && image.height <= 4_096)
					#expect(image.width * image.height <= 2_000_000)
					let bytes = try #require(image.dataProvider?.data) as Data
					#expect(bytes.contains
					{
						$0 != 0
					})
				}
				let lightBytes = try #require(pair.light.dataProvider?.data) as Data
				let darkBytes = try #require(pair.dark.dataProvider?.data) as Data
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
