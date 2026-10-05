import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct UserMessageImageAttachmentsTests
{
	@Test func thumbnailsStayAboveTheRequestAndWrapWithinTheReadingWidth() async throws
	{
		_ = NSApplication.shared
		let reference = try #require(UserMessageReference(
			json: [
				"type": "localImage",
				"path": "/tmp/missing-attachment-fixture.png"
			],
			id: "image"
		))
		let body = "Make such groups collapsed by default when opening a conversation in codex gui"
		let content = await ConversationContentCache().content(
			body: body,
			markdown: true
		)
		let attachments = Array(
			repeating: reference,
			count: 5
		)
		let item = ConversationCollectionItem()
		item.configure(
			ConversationEntry(
				id: "turn:user",
				kind: .user,
				title: "You",
				body: body,
				imageAttachments: attachments
			),
			content: content,
			expanded: false,
			onToggle:
			{
			}
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 736,
				height: 300
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = item
		for width: CGFloat in [736, 320, 120]
		{
			let size = ConversationCollectionItem.itemSize(
				content: content,
				width: width,
				expandable: false,
				kind: .user,
				imageAttachmentCount: attachments.count
			)
			window.setContentSize(size)
			item.view.layoutSubtreeIfNeeded()
			let strip = try #require(descendants(item.view).compactMap
			{
				$0 as? UserMessageImageAttachmentsView
			}.first)
			let buttons = strip.subviews.compactMap
			{
				$0 as? NSButton
			}
			#expect(buttons.count == 5)
			#expect(buttons.allSatisfy
			{
				$0.frame.minX >= 0 && $0.frame.maxX <= width
			})
			#expect(buttons
				.allSatisfy
				{
					$0.frame.minY >= 0 && $0.frame.maxY <= strip.bounds.height
				})
			#expect(abs(try #require(buttons.last).frame.maxX - width) < 0.5)
			for index in 1 ..< buttons.count
			{
				#expect(!buttons[index - 1].frame.intersects(buttons[index].frame))
			}
			let text = try #require(descendants(item.view).compactMap
			{
				$0 as? NSTextView
			}.first)
			let textFrame = text.convert(
				text.bounds,
				to: item.view
			)
			#expect(textFrame.maxY < strip.frame.minY)
			#expect(text.string == body)
			#expect(size.height > strip.bounds.height)
		}
	}

	@Test func unavailableImagesKeepTheirNamesAndReuseClearsOldControls() async throws
	{
		_ = NSApplication.shared
		let reference = try #require(UserMessageReference(
			json: [
				"type": "localImage",
				"path": "/tmp/missing-attachment-fixture.png"
			],
			id: "image"
		))
		let strip = UserMessageImageAttachmentsView()
		strip.configure([reference])
		let oldButton = try #require(strip.subviews.first as? NSButton)
		await strip.waitForImages()
		#expect(oldButton
			.accessibilityLabel() == "Image unavailable: missing-attachment-fixture.png")
		#expect(!oldButton.isEnabled)
		strip.configure([])
		#expect(strip.subviews.isEmpty)
		#expect(strip.isHidden)
		#expect(oldButton.target == nil && oldButton.action == nil)
	}

	@Test func imageOnlyMessagesHaveNoEmptyBubbleAndTextAnchorsIncludeThumbnails() async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		let empty = await cache.content(
			body: "",
			markdown: true
		)
		#expect(ConversationCollectionItem.itemSize(
			content: empty,
			width: 320,
			expandable: false,
			kind: .user,
			imageAttachmentCount: 2
		).height == 80)
		let content = await cache.content(
			body: "First line\nSecond line",
			markdown: true
		)
		let without = try #require(ConversationCollectionItem.textReadingOffset(
			content: content,
			width: 320,
			kind: .user,
			character: 0,
			lineOffset: 0
		))
		let withImages = try #require(ConversationCollectionItem.textReadingOffset(
			content: content,
			width: 320,
			kind: .user,
			character: 0,
			lineOffset: 0,
			imageAttachmentCount: 5
		))
		#expect(withImages - without == 176)
		#expect(ConversationCollectionItem.textReadingAnchor(
			content: content,
			width: 320,
			kind: .user,
			offset: 40,
			imageAttachmentCount: 5
		) == nil)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
