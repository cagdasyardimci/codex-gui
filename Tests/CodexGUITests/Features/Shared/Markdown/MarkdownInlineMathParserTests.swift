import Foundation
import Testing

@testable import CodexGUI

struct MarkdownInlineMathParserTests
{
	@Test func inlineTeXSurvivesCommonMarkAndPreservesExactUnicodeSource() throws
	{
		let first = #"\(a_b + c_d + \text{café 😀} + *x*\)"#
		let second = #"\(\frac{1}{2}\)"#
		let source = "Before 😀 " + first + " between " + second + " after."
		let parsed = parse(source)
		let math = parsed.runs.compactMap(\.style.richBlock)
		#expect(math.map(\.source) == [first, second])
		#expect(math.map(\.payload) == [#"a_b + c_d + \text{café 😀} + *x*"#, #"\frac{1}{2}"#])
		#expect(math.allSatisfy
		{
			$0.isInline
		})
		#expect(parsed.runs.map(\.text).joined() == "Before 😀 \u{FFFC} between \u{FFFC} after.")
		#expect(MarkdownPlainTextRenderer.render(parsed) == source)
	}

	@Test func codeDestinationsAndEscapedDelimitersKeepLiteralSemantics()
	{
		let source = #"`\(inline\)` [label](https://example.com/\(path\)) "#
			+ #"<https://example.com/\(auto\)> \\(escaped\\) $x+y$"#
			+ "\n\n```tex\n\\(fenced\\)\n```"
		let parsed = parse(source)
		#expect(parsed.runs.allSatisfy
		{
			$0.style.richBlock == nil
		})
		#expect(parsed.codeBlocks == [#"\(fenced\)"# + "\n"])
		#expect(parsed.runs.contains
		{
			$0.style.code && $0.text == #"\(inline\)"#
		})
		#expect(parsed.runs.contains
		{
			$0.text.contains("$x+y$")
		})
		#expect(parsed.runs.contains
		{
			$0.style.link == "https://example.com/(path)"
		})
	}

	@Test func inlineMathRetainsHeadingListQuoteTableAndLinkLabelStyles() throws
	{
		let source = #"# Heading \(h_i\)"# + "\n\n"
			+ #"- **\(b_i\)** and [\(l_i\)](https://example.com)"# + "\n\n"
			+ #"> Quote \(q_i\)"# + "\n\n"
			+ "| Formula |\n| --- |\n| " + #"\(t_i\)"# + " |"
		let parsed = parse(source)
		let runs = parsed.runs.filter
		{
			$0.text == "\u{FFFC}" && $0.style.richBlock?.isInline == true
		}
		try #require(runs.count == 5)
		#expect(runs[0].style.heading == 1)
		#expect(runs[1].style.bold && runs[1].style.listDepth == 1)
		#expect(runs[2].style.link == "https://example.com" && runs[2].style.listDepth == 1)
		#expect(runs[3].style.quoteDepth == 1)
		#expect(runs[4].style.tableCell?.row == 1)
	}

	@Test func inlineReplacementPreservesFollowingRichBlockAndCodeSourceLocations() throws
	{
		let math = #"\(α_i + 😀\)"#
		let image = "![image](/tmp/math.png)"
		let display = "$$\nx^2\n$$"
		let parsed = parse(math + "\n\n" + image + "\n\n" + display
			+ "\n\n```swift\nlet value = 1\n```")
		#expect(parsed.runs.filter
		{
			$0.text == "\u{FFFC}"
		}
		.compactMap(\.style.richBlock).map(\.source) == [math, image, display])
		let codeRange = try #require(parsed.codeBlockRanges.first)
		let text = parsed.runs.map(\.text).joined() as NSString
		#expect(text.substring(with: codeRange) == "let value = 1\n")
	}

	@Test func unfinishedEmptyAndMultilineDelimitersDoNotBecomeAttachments()
	{
		for source in [#"\(unterminated"#, #"\( \)"#, "\\(first\nsecond\\)"]
		{
			#expect(parse(source).runs.allSatisfy
			{
				$0.style.richBlock == nil
			})
		}
	}

	@Test func manyUnmatchedOpenersKeepLaterLineAndLinkScopeFormulas() throws
	{
		let unmatched = String(
			repeating: #"\(unclosed "#,
			count: 8_192
		)
		let formula = #"\(x_i\)"#
		let source = unmatched + "**boundary** " + unmatched + "\nnext " + formula
		let parsed = parse(source)
		let math = parsed.runs.filter
		{
			$0.text == "\u{FFFC}"
		}
		.compactMap(\.style.richBlock)
		#expect(math.map(\.source) == [formula])
		let plain = MarkdownPlainTextRenderer.render(parsed)
		#expect(plain.hasPrefix(String(
			repeating: "(unclosed ",
			count: 8_192
		)))
		#expect(plain.hasSuffix("next " + formula))

		let linkSource = #"[label \(unclosed](https://example.com) "# + formula
		let linkParsed = parse(linkSource)
		let linkMath = linkParsed.runs.filter
		{
			$0.text == "\u{FFFC}"
		}
		.compactMap(\.style.richBlock)
		#expect(linkMath.map(\.source) == [formula])
		#expect(linkParsed.runs.contains
		{
			$0.style.link == "https://example.com" && $0.text == "label (unclosed"
		})
	}

	private func parse(_ source: String) -> ParsedMarkdownContent
	{
		MarkdownContentParser.parse(
			source,
			markdown: true
		)
	}
}
