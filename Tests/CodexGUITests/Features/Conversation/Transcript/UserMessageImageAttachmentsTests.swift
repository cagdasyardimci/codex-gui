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

	@Test func localFileURLsFinishLoadingAndClearProgress() async throws
	{
		_ = NSApplication.shared
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("attachment \(UUID().uuidString).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 8,
			pixelsHigh: 6,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		try #require(bitmap.representation(
			using: .png,
			properties: [:]
		)).write(to: url)
		let reference = try #require(UserMessageReference(
			json: ["type": "localImage", "path": url.absoluteString],
			id: "image"
		))
		let strip = UserMessageImageAttachmentsView()
		strip.configure([reference])
		let button = try #require(strip.subviews.first as? NSButton)
		#expect(!button.isEnabled)
		#expect(button.accessibilityLabel() == "Loading attached image: \(reference.name)")
		#expect(button.subviews.contains
		{
			$0 is NSProgressIndicator
		})
		await strip.waitForImages()
		#expect(button.isEnabled)
		#expect(button.accessibilityLabel() == "Open attached image: \(reference.name)")
		#expect(!button.subviews.contains
		{
			$0 is NSProgressIndicator
		})
		let preview = try #require(await SourceThumbnailLoader.load(path: url.absoluteString))
		let image = try #require(NSImage(data: preview))
		#expect(image.size.width > 0 && image.size.height > 0)
	}

	@Test func reuseRejectsEarlierImageCompletion() async throws
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("old-image-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 8,
			pixelsHigh: 6,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		try #require(bitmap.representation(
			using: .png,
			properties: [:]
		)).write(to: url)
		let old = try #require(UserMessageReference(
			json: ["type": "localImage", "path": url.path],
			id: "old"
		))
		let current = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/missing-\(UUID()).png"],
			id: "current"
		))
		let strip = UserMessageImageAttachmentsView()
		strip.configure([old])
		let detached = try #require(strip.subviews.first as? NSButton)
		strip.configure([current])
		await strip.waitForImages()
		let button = try #require(strip.subviews.first as? NSButton)
		#expect(button !== detached)
		#expect(detached.target == nil && detached.action == nil)
		#expect(button.accessibilityLabel() == "Image unavailable: \(current.name)")
		#expect(!button.isEnabled)
		#expect(!button.subviews.contains
		{
			$0 is NSProgressIndicator
		})
	}

	@Test func protocolInlineImagesReachTheTranscriptAndFinishLoading() async throws
	{
		_ = NSApplication.shared
		let path = "data:image/png;base64," + (try inlinePNG()).base64EncodedString()
		let item = try #require(CodexItem(json: [
			"id": "user",
			"type": "userMessage",
			"content": [
				["type": "text", "text": "Read this image."],
				["type": "image", "url": path],
			],
		]))
		let entry = ConversationContentReducer.entry(
			for: item,
			id: "turn:user"
		)
		#expect(entry.body == "Read this image.")
		#expect(entry.imageAttachments.map(\.path) == [path])
		let strip = UserMessageImageAttachmentsView()
		strip.configure(entry.imageAttachments)
		let button = try #require(strip.subviews.first as? NSButton)
		await strip.waitForImages()
		#expect(button.isEnabled)
		#expect(button.accessibilityLabel() == "Open attached image: Attached image")
		#expect(button.accessibilityHelp() == "Inline image")
		#expect(!button.subviews.contains
		{
			$0 is NSProgressIndicator
		})
	}

	@Test func inlineImagesOpenInANativePanelAndReuseOrDetachDismissesIt() async throws
	{
		_ = NSApplication.shared
		let reference = try #require(UserMessageReference(
			json: [
				"type": "image",
				"url": "data:image/png;base64," + (try inlinePNG()).base64EncodedString(),
			],
			id: "inline"
		))
		let strip = UserMessageImageAttachmentsView()
		let parent = NSWindow(
			contentRect: NSRect(
				x: 100,
				y: 100,
				width: 600,
				height: 400
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		parent.isReleasedWhenClosed = false
		parent.contentView = strip
		defer
		{
			strip.configure([])
			parent.orderOut(nil)
		}
		strip.configure([reference])
		await strip.waitForImages()
		let button = try #require(strip.subviews.first as? NSButton)
		button.performClick(nil)
		await strip.waitForInlinePreview()
		let preview = try #require(parent.childWindows?.first)
		#expect(preview.accessibilityIdentifier() == "inline-image-preview")
		#expect(preview.title == "Attached image")
		let previewContent = try #require(preview.contentView)
		let imageView = try #require(descendants(previewContent).compactMap
		{
			$0 as? NSImageView
		}.first)
		#expect(imageView.image != nil)
		strip.configure([])
		#expect(parent.childWindows?.isEmpty != false)
		#expect(!preview.isVisible)
		#expect(button.target == nil && button.action == nil)

		strip.configure([reference])
		await strip.waitForImages()
		let current = try #require(strip.subviews.first as? NSButton)
		current.performClick(nil)
		await strip.waitForInlinePreview()
		let reopened = try #require(parent.childWindows?.first)
		parent.contentView = NSView()
		#expect(parent.childWindows?.isEmpty != false)
		#expect(!reopened.isVisible)
	}

	@Test func unavailableInlineImagesClearProgressAndEarlierResultsCannotReplaceReuse(
	) async throws
	{
		let first = try #require(UserMessageReference(
			json: [
				"type": "image",
				"url": "data:image/png;base64," + (try inlinePNG()).base64EncodedString(),
			],
			id: "first"
		))
		let invalid = try #require(UserMessageReference(
			json: ["type": "image", "url": "data:image/png;base64,%%%"],
			id: "invalid"
		))
		let strip = UserMessageImageAttachmentsView()
		strip.configure([first])
		let detached = try #require(strip.subviews.first as? NSButton)
		strip.configure([invalid])
		await strip.waitForImages()
		let button = try #require(strip.subviews.first as? NSButton)
		#expect(button !== detached)
		#expect(detached.target == nil && detached.action == nil)
		#expect(button.accessibilityLabel() == "Image unavailable: Attached image")
		#expect(!button.isEnabled)
		#expect(!button.subviews.contains
		{
			$0 is NSProgressIndicator
		})
	}

	private func inlinePNG() throws -> Data
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 8,
			pixelsHigh: 6,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0
		))
		return try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
