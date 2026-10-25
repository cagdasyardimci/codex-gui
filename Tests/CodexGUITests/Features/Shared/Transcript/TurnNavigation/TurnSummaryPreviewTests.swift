import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnSummaryPreviewTests
{

	@Test func previewHighlightsMarkdownAndVisibleWebLinks() throws
	{
		_ = NSApplication.shared
		let summary = ConversationTurnSummary.make(from: [
			entry(
				"turn:request",
				.user,
				"Use a favicon"
			),
			entry(
				"turn:reply",
				.agent,
				"See [documentation](https://example.org/guide) and https://example.com/path."
			),
		])[0]
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: false
		)
		let stack = try #require(preview.subviews.first as? NSStackView)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		let text = reply.attributedStringValue
		let labelRange = (text.string as NSString).range(of: "documentation")
		#expect((text.attribute(
			.link,
			at: labelRange.location,
			effectiveRange: nil
		) as? URL)?
			.absoluteString == "https://example.org/guide")
		var iconCount = 0
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
			if value is WebLinkFaviconAttachment
			{
				iconCount += 1
			}
		}
		#expect(iconCount == 2)
		#expect(reply.isSelectable && reply.allowsEditingTextAttributes)
		let cached = ConversationTurnSummary(
			turnID: "cached",
			entryID: "cached:reference",
			title: "Cached turn",
			reply: "Visit https://example.net/page"
		)
		preview.render(cached)
		#expect(reply.attributedStringValue.string.contains("https://example.net/page"))
		#expect(reply.attributedStringValue.attribute(
			.attachment,
			at: 6,
			effectiveRange: nil
		) is WebLinkFaviconAttachment)
		#expect((reply.attributedStringValue.attribute(
			.link,
			at: 7,
			effectiveRange: nil
		) as? URL)?.absoluteString == "https://example.net/page")
		let fromCache = ConversationTurnSummary.navigation(
			references: [ConversationTurnReference(
				id: "cached",
				status: "completed"
			)],
			loaded: [],
			cached: [ConversationTurnPreview(
				turnID: "cached",
				entryID: "cached:request",
				title: "Cached turn",
				reply: "See documentation.",
				replySource: "See [documentation](https://example.org/guide)."
			)]
		)[0]
		preview.render(fromCache)
		let cachedText = reply.attributedStringValue
		let cachedLabel = (cachedText.string as NSString).range(of: "documentation")
		#expect((cachedText.attribute(
			.link,
			at: cachedLabel.location,
			effectiveRange: nil
		) as? URL)?.absoluteString == "https://example.org/guide")
	}

	private func entry(
		_ id: String,
		_ kind: ConversationEntryKind,
		_ body: String
	) -> ConversationEntry
	{
		ConversationEntry(
			id: id,
			kind: kind,
			title: "",
			body: body
		)
	}

}
