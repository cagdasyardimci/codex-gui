import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct MarkdownMathRendererTests
{
	@Test(.appKitIsolation)
	func preparedMathUsesKaTeXGeometryAndPreservesSource() async throws
	{
		_ = NSApplication.shared
		let displaySource = "$$\n\\frac{a+b}{c+d}\n$$"
		let source = #"Inline \(x^2 + y^2 = z^2\)."# + "\n\n" + displaySource
		let parsed = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let typography = TypographyConfiguration(
			uiSize: 14,
			contentSize: 15,
			codeSize: 12
		)
		let images = await MarkdownMathRenderer.prepare(
			parsed: parsed,
			typography: typography,
			filePreview: true
		)
		let inline = try #require(images.first(where:
			{
				$0.key.inline
			})?.value)
		let display = try #require(images.first(where:
			{
				!$0.key.inline
			})?.value)
		// The same KaTeX fonts retain subpixel layout differences across WebKit and Chromium.
		// Keep this below a quarter physical pixel at 2x; do not rescale individual formulas.
		#expect(abs(inline.lightSize.width - 90.828) < 0.125)
		#expect(abs(inline.lightSize.height - 20) < 0.125)
		#expect(abs(display.lightSize.width - 41) < 0.05)
		#expect(abs(display.lightSize.height - 36.258) < 0.05)
		#expect(inline.baselineDescent >= 0 && inline.baselineDescent < inline.lightSize.height)
		#expect(inline.light.representations.allSatisfy
		{
			$0 is NSPDFImageRep
		})
		let rendered = MarkdownAttributedStringRenderer.render(
			parsed.runs,
			preparedMathImages: images,
			mathFontSize:
			{
				style, inline in
				FileMarkdownStyling.mathFontSize(
					style: style,
					inline: inline,
					configuration: typography
				)
			}
		)
		var sources: [String] = []
		rendered.enumerateAttribute(
			.markdownSourceText,
			in: NSRange(
				location: 0,
				length: rendered.length
			)
		)
		{
			value, _, _ in
			if let value = value as? String
			{
				sources.append(value)
			}
		}
		#expect(sources.contains(#"\(x^2 + y^2 = z^2\)"#))
		#expect(sources.contains(displaySource))
	}

	@Test(.appKitIsolation)
	func invalidMathAndExhaustedBudgetRetainSourceFallback() async throws
	{
		_ = NSApplication.shared
		let parsed = MarkdownContentParser.parse(
			#"\(\notARealCommand{x}\)"#,
			markdown: true
		)
		#expect(await MarkdownMathRenderer.prepare(parsed: parsed).isEmpty)
		#expect(await MarkdownMathRenderer.prepare(
			parsed: parsed,
			maximumPreparedPixels: 0
		)
		.isEmpty)
		#expect(!MarkdownMathRenderer.admits(String(
			repeating: "{",
			count: 33
		)))
		let rendered = MarkdownAttributedStringRenderer.render(parsed.runs)
		let range = NSRange(
			location: 0,
			length: rendered.length
		)
		var fallback: MarkdownInlineMathAttachment?
		rendered.enumerateAttribute(
			.attachment,
			in: range
		)
		{
			value, _, _ in fallback = value as? MarkdownInlineMathAttachment
		}
		let attachment = try #require(fallback)
		#expect(!attachment.rendersNativeImage)
		#expect(attachment.source == #"\(\notARealCommand{x}\)"#)
	}
}
