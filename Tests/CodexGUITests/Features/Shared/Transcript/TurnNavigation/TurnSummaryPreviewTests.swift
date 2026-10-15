import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnSummaryPreviewTests
{
	@Test func previewFitsAndBookmarkButtonDispatches() throws
	{
		_ = NSApplication.shared
		let summary = ConversationTurnSummary(
			turnID: "turn",
			entryID: "turn:request",
			title: String(
				repeating: "A long request ",
				count: 30
			),
			reply: String(
				repeating: "The reply contains details. ",
				count: 30
			)
		)
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: false
		)
		let window = NSWindow(
			contentRect: preview.bounds,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = preview
		window.displayIfNeeded()
		defer
		{
			window.contentView = nil
		}
		preview.layoutSubtreeIfNeeded()
		let stack = try #require(preview.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let button = try #require(header.arrangedSubviews.last as? NSButton)
		#expect(header.frame.width == preview.bounds.width - 20)
		#expect(header.frame.height >= 16)
		#expect(button.frame.width == 18)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		#expect(reply.frame.height > 40)
		#expect(reply.cell?.wraps == true)
		#expect(reply.stringValue.hasSuffix("…"))
		#expect(preview.cardHeight == preview.frame.height)
		let multilineHeight = preview.cardHeight
		preview.render(ConversationTurnSummary(
			turnID: "turn",
			entryID: "turn:request",
			title: "Short request",
			reply: "Short reply"
		))
		#expect(preview.cardHeight < multilineHeight)
		var clicked = false
		preview.onBookmark =
		{
			clicked = true
		}
		button.dispatchConfiguredAction()
		#expect(clicked)
		preview.setBookmarked(true)
		#expect(button.accessibilityLabel() == "Remove turn bookmark")

	}

	@Test func compactPreviewUsesAllThreeLinesForContent() throws
	{
		_ = NSApplication.shared
		let summary = ConversationTurnSummary.make(from: [
			entry(
				"turn:request",
				.user,
				"Task names in CodexGUI under project tabs"
			),
			entry(
				"turn:reply",
				.agent,
				"Implemented all six sidebar changes:\n\n"
					+ "- Reduced task indentation.\n"
					+ "- Added distinct expanded/collapsed project icons.\n"
					+ "- Fixed ellipsis truncation."
			),
		])[0]
		let preview = TurnSummaryPreview(
			summary: summary,
			bookmarked: false
		)
		let stack = try #require(preview.subviews.first as? NSStackView)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		#expect(!reply.stringValue.contains("\n\n"))
		#expect(reply.stringValue.contains("• Reduced task indentation."))
		#expect(reply.stringValue.contains("• Added distinct"))
		#expect(reply.stringValue.hasSuffix("…"))
	}

	@Test func linkedTitleWrapsAndExpandsCard() throws
	{
		_ = NSApplication.shared
		let preview = TurnSummaryPreview(
			summary: ConversationTurnSummary(
				turnID: "turn",
				entryID: "turn:request",
				title: "Short request",
				reply: "Short reply"
			),
			bookmarked: false
		)
		let shortHeight = preview.cardHeight
		preview.render(ConversationTurnSummary(
			turnID: "turn",
			entryID: "turn:request",
			title: "Lets go with using "
				+ "[https://www.dicebear.com/styles/gaze/presets/]"
				+ "(https://www.dicebear.com/styles/gaze/presets/) geometric preset",
			reply: "Short reply"
		))
		let window = NSWindow(
			contentRect: preview.bounds,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentView = preview
		defer
		{
			window.contentView = nil
		}
		preview.layoutSubtreeIfNeeded()
		let stack = try #require(preview.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let title = try #require(header.arrangedSubviews.first as? NSTextField)
		let bookmark = try #require(header.arrangedSubviews.last as? NSButton)
		#expect(preview.cardHeight > shortHeight)
		#expect(header.frame.height > 18)
		#expect(title.frame.height > 18)
		#expect(title.maximumNumberOfLines == 2)
		#expect(title.cell?.wraps == true)
		#expect(bookmark.alignmentRect(forFrame: bookmark.frame).maxY == header.bounds.maxY)
		#expect(title.stringValue.contains("geometric preset"))
		#expect(!title.stringValue.contains("](https://"))
		let titleTextHeight = ceil(title.attributedStringValue.boundingRect(
			with: NSSize(
				width: title.frame.width,
				height: 10000
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		).height)
		#expect(titleTextHeight <= title.frame.height)
		var faviconCount = 0
		title.attributedStringValue.enumerateAttribute(
			.attachment,
			in: NSRange(
				location: 0,
				length: title.attributedStringValue.length
			),
			options: []
		)
		{
			value, _, _ in
			if value is WebLinkFaviconAttachment
			{
				faviconCount += 1
			}
		}
		#expect(faviconCount == 1)
	}

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
