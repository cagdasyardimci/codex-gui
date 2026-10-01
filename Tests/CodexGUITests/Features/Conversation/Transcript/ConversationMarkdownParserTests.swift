import Foundation
import Testing

@testable import CodexGUI

struct ConversationMarkdownParserTests
{
	@Test func atxAndSetextHeadingsHaveTheirDeclaredLevels()
	{
		let parsed = parse("# First\n\nSecond\n======\n\nThird\n-----\n\n### Fourth ###")
		#expect(text(parsed) == "First\nSecond\nThird\nFourth")
		for (title, level) in [("First", 1), ("Second", 1), ("Third", 2), ("Fourth", 3)]
		{
			#expect(parsed.runs.contains
			{
				$0.text.contains(title) && $0.style.heading == level
			})
		}
	}

	@Test func paragraphsFoldSoftBreaksAndRetainBothHardBreakForms()
	{
		let parsed = parse("soft\ncontinuation\n\nhard  \nbreak\n\nslash\\\nbreak")
		#expect(text(parsed) == "soft continuation\nhard\nbreak\nslash\nbreak")
		#expect(parsed.codeBlocks.isEmpty)
	}

	@Test func ordinaryPunctuationKeepsStraightQuotesHyphensAndPeriods()
	{
		let body = "\"straight\" 'apostrophe' -- --- ..."
		#expect(text(parse(body)) == body)
	}

	@Test func nestedListsPreserveHierarchyOrderedStartAndTaskState()
	{
		let body = """
		3. ordered first
		8. ordered second
		   - nested bullet
		     - deeper bullet

		- [ ] pending
		- [x] complete
		"""
		let parsed = parse(body)
		let display = text(parsed)
		#expect(display.contains("3. ordered first\n4. ordered second"))
		#expect(display.contains("◦ nested bullet"))
		#expect(display.contains("▪ deeper bullet"))
		#expect(display.contains("☐ pending\n☑ complete"))
		let nested = parsed.runs.first
		{
			$0.text.contains("nested bullet")
		}
		let deeper = parsed.runs.first
		{
			$0.text.contains("deeper bullet")
		}
		#expect((nested?.style.listDepth ?? 0) > 0)
		#expect((deeper?.style.listDepth ?? 0) > (nested?.style.listDepth ?? 0))
	}

	@Test func nonOneOrderedMarkerCannotInterruptAParagraph()
	{
		let parsed = parse("paragraph\n3. remains paragraph\n\n3. actual list")
		#expect(text(parsed).contains("paragraph 3. remains paragraph\n3. actual list"))
		let paragraph = parsed.runs.first
		{
			$0.text.contains("remains paragraph")
		}
		let list = parsed.runs.first
		{
			$0.text.contains("actual list")
		}
		#expect(paragraph?.style.listDepth == 0)
		#expect((list?.style.listDepth ?? 0) > 0)
	}

	@Test func emptyListItemKeepsItsMarkerBeforePopulatedItems()
	{
		let parsed = parse("-\n- populated\n\n- [ ] pending\n- [x] complete")
		#expect(text(parsed).hasPrefix("• \n• populated"))
		#expect(text(parsed).contains("☐ pending\n☑ complete"))
	}

	@Test func blockquotesPreserveNestingAndInlineFormatting()
	{
		let parsed = parse("> outside **bold**\n>\n> > inside *italic*\n\nordinary")
		#expect(text(parsed).contains("outside bold"))
		#expect(text(parsed).contains("inside italic"))
		#expect(!text(parsed).contains(">"))
		#expect(!text(parsed).contains("│"))
		#expect(parsed.runs.contains
		{
			$0.text == "bold" && $0.style.bold && $0.style.quoteDepth == 1
		})
		#expect(parsed.runs.contains
		{
			$0.text == "italic" && $0.style.italic && $0.style.quoteDepth == 2
		})
	}

	@Test func nestedEmphasisStrikethroughAndInlineCodeRemainSeparate()
	{
		let parsed = parse("***both*** ~~deleted~~ `literal *markers*` ordinary")
		#expect(text(parsed) == "both deleted literal *markers* ordinary")
		#expect(parsed.runs.contains
		{
			$0.text == "both" && $0.style.bold && $0.style.italic
		})
		#expect(parsed.runs.contains
		{
			$0.text == "deleted" && $0.style.strikethrough
		})
		#expect(parsed.runs.contains
		{
			$0.text == "literal *markers*" && $0.style.code && !$0.style.codeBlock
		})
		#expect(parsed.codeBlocks.isEmpty)
		#expect(parsed.codeBlockRanges.isEmpty)
	}

	@Test func referenceAndAutomaticLinksResolveDestinations()
	{
		let parsed = parse(
			"[reference][docs] <https://example.com/auto> <reader@example.com>\n\n"
				+ "[docs]: https://example.com/reference \"Documentation\""
		)
		#expect(text(parsed).contains("reference https://example.com/auto reader@example.com"))
		#expect(!text(parsed).contains("[docs]"))
		for (label, destination) in [
			("reference", "https://example.com/reference"),
			("https://example.com/auto", "https://example.com/auto"),
			("reader@example.com", "mailto:reader@example.com"),
		]
		{
			#expect(parsed.runs.contains
			{
				$0.text == label && $0.style.link == destination
			})
		}
	}

	@Test func escapesAndEntitiesAreDecodedAndThematicBreakIsVisible()
	{
		let parsed = parse("\\*literal\\* &amp; &lt; &gt; &copy; &#x1F600; café\n\n---\n\nend")
		let display = text(parsed)
		#expect(display.contains("*literal* & < > © 😀 café"))
		#expect(!display.contains("&amp;"))
		#expect(!display.contains("---"))
		#expect(parsed.runs.contains
		{
			$0.text == "\u{FFFC}" && $0.style.thematicBreak
		})
		#expect(parsed.runs.filter
		{
			$0.text.contains("literal")
		}.allSatisfy
		{
			!$0.style.italic
		})
	}

	@Test func rawHTMLAndImagesHaveReadableLiteralFallbacks()
	{
		let parsed = parse(
			"<div>raw &amp; html</div>\n\n"
				+ "before <span>inline</span> ![diagram **description**](https://example.com/a.png)"
		)
		let display = text(parsed)
		#expect(display.contains("<div>raw &amp; html</div>"))
		#expect(display.contains("<span>inline</span>"))
		#expect(display.contains("[Image: diagram description] (https://example.com/a.png)"))
		#expect(parsed.codeBlocks.isEmpty)
	}

	@Test func fencedIndentedAndUnfinishedCodePreserveExactCopyText()
	{
		let body = """
		````swift
		let value = "  exact  "
		```
		````

		~~~text
		  café 😀
		~~~

		    indented
		      nested spaces

		```text
		unfinished
		"""
		let parsed = parse(body)
		#expect(parsed.codeBlocks == [
			"let value = \"  exact  \"\n```\n",
			"  café 😀\n",
			"indented\n  nested spaces\n",
			"unfinished\n",
		])
		#expect(parsed.codeBlockRanges.count == parsed.codeBlocks.count)
		for (range, code) in zip(
			parsed.codeBlockRanges,
			parsed.codeBlocks
		)
		{
			#expect((text(parsed) as NSString).substring(with: range) == code)
		}
		#expect(parsed.runs.filter
		{
			$0.style.codeBlock
		}.allSatisfy
		{
			!$0.style.code
		})
	}

	@Test func codeRangesUseUTF16AfterUnicodeListsQuotesAndTables()
	{
		let body = """
		😀 café é 👨‍👩‍👧‍👦

		- list 中文

		> quote Ελληνικά

		| First | Second |
		| --- | --- |
		| 日本語 | 😀 |

		```text
		  exact 😀\ttext
		```

		> ~~~text
		> quoted code
		> ~~~

		- nested code:

		  ```text
		  list code
		  ```
		"""
		let parsed = parse(body)
		let display = text(parsed) as NSString
		#expect(parsed.codeBlocks == ["  exact 😀\ttext\n", "quoted code\n", "list code\n"])
		#expect(parsed.codeBlockRanges.count == 3)
		for (range, code) in zip(
			parsed.codeBlockRanges,
			parsed.codeBlocks
		)
		{
			#expect(range == display.range(of: code))
			#expect(range.length == code.utf16.count)
			#expect(display.substring(with: range) == code)
		}
	}

	@Test func emptyFencesAndUnicodeSeparatorsHaveExactCodeRanges()
	{
		let code = "left\u{2028}middle\u{2029}right\n"
		let parsed = parse("```text\n```\n\n~~~text\n" + code + "~~~")
		#expect(parsed.codeBlocks == ["", code])
		#expect(parsed.codeBlockRanges.count == 2)
		#expect(parsed.codeBlockRanges.first?.length == 0)
		for (range, copied) in zip(
			parsed.codeBlockRanges,
			parsed.codeBlocks
		)
		{
			#expect((text(parsed) as NSString).substring(with: range) == copied)
			#expect(range.length == copied.utf16.count)
		}
	}

	@Test func displayMathKeepsRawEscapesAndFollowingCodeUsesRenderedUTF16Offsets() throws
	{
		let payload = #"\int_0^1 x^2\,dx = \frac{1}{3}"#
		let source = "$$\n" + payload + "\n$$"
		let parsed = parse("😀 café\n\n" + source + "\n\n```swift\nlet value = \"😀\"\n```")
		let math = try #require(parsed.runs.compactMap(\.style.richBlock).first)
		#expect(math.kind == .math)
		#expect(math.source == source)
		#expect(math.payload == payload)
		#expect(text(parsed).contains("\u{FFFC}"))
		#expect(parsed.codeBlocks == ["let value = \"😀\"\n"])
		let range = try #require(parsed.codeBlockRanges.first)
		#expect(range == (text(parsed) as NSString).range(of: parsed.codeBlocks[0]))
		#expect((text(parsed) as NSString).substring(with: range) == parsed.codeBlocks[0])
		let brackets = parse("\\[\n\\frac{1}{2}\n\\]")
		let bracketMath = try #require(brackets.runs.compactMap(\.style.richBlock).first)
		#expect(bracketMath.source == "\\[\n\\frac{1}{2}\n\\]")
		#expect(bracketMath.payload == #"\frac{1}{2}"#)
		#expect(parse("Inline $E = mc^2$").runs.allSatisfy
		{
			$0.style.richBlock == nil
		})
	}

	@Test func mermaidAttachmentsKeepSourceAndUnfinishedFencesStayReadableCode() throws
	{
		let code = "flowchart LR\n    A[Source] --> B[Rendered]\n"
		let source = "```mermaid\n" + code + "```"
		let complete = parse(source)
		let diagram = try #require(complete.runs.compactMap(\.style.richBlock).first)
		#expect(diagram.kind == .diagram)
		#expect(diagram.source == source)
		#expect(diagram.payload == code)
		#expect(complete.codeBlocks == [code])
		let range = try #require(complete.codeBlockRanges.first)
		#expect(range.length == 1)
		#expect((text(complete) as NSString).substring(with: range) == "\u{FFFC}")
		let unfinished = parse("```mermaid\n" + code)
		#expect(unfinished.runs.allSatisfy
		{
			$0.style.richBlock == nil
		})
		#expect(unfinished.codeBlocks == [code])
		#expect((text(unfinished) as NSString).substring(with: try #require(
			unfinished.codeBlockRanges.first
		)) == code)
	}

	@Test func literalModePreservesEveryMarkerAndWhitespaceWithoutBlockMetadata()
	{
		let body = "  # heading\n\n| a | b |\n| --- | --- |\n> quote\n```x```\n😀  "
		let parsed = ConversationContentParser.parse(
			body,
			markdown: false
		)
		#expect(text(parsed) == body)
		#expect(parsed.codeBlocks.isEmpty)
		#expect(parsed.codeBlockRanges.isEmpty)
		#expect(parsed.runs.allSatisfy
		{
			$0.style.monospaced && !$0.style.codeBlock && $0.style.tableCell == nil
		})
	}

	private func parse(_ body: String) -> ParsedConversationContent
	{
		ConversationContentParser.parse(
			body,
			markdown: true
		)
	}

	private func text(_ parsed: ParsedConversationContent) -> String
	{
		parsed.runs.map(\.text).joined()
	}
}
