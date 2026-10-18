import Foundation
import Testing

@testable import CodexGUI

struct MarkdownPlainTextRendererTests
{
	@Test func textOnlyRenderingMatchesLinkedRenderingAcrossBlocksAndUnicode()
	{
		let source = "😀 [**café** guide](https://example.com) and [local](/tmp/file)\n\n"
			+ "- First\n- Second\n\n```text\n  exact 😀\n```\n\n$$\nα + β\n$$"
		let content = MarkdownContentParser.parse(
			source,
			markdown: true
		)
		let linked = MarkdownPlainTextRenderer.renderWithLinks(content)
		#expect(MarkdownPlainTextRenderer.render(content).utf8.elementsEqual(linked.text.utf8))
		#expect(linked.links.count == 1)
		#expect((linked.text as NSString).substring(with: linked.links[0].range) == "café guide")
		#expect(linked.links[0].destination == "https://example.com")
		#expect(linked.text.contains("  exact 😀") && linked.text.contains("α + β"))
	}
}
