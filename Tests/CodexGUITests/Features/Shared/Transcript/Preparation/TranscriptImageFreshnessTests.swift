import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite @MainActor
struct TranscriptImageFreshnessTests
{
	@Test func replacedLocalImageRefreshesPreparedMessagesActivityAndExpandedViewer() async throws
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("transcript-freshness-\(UUID()).png")
		try await BackgroundTestWork.perform
		{
			try writeImage(
				to: url,
				height: 6,
				modifiedAt: 1_000
			)
		}
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let cache = ConversationContentCache()
			let coordinator = TranscriptPreparationCoordinator()
			let item = ConversationActivityCollectionItem()
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 800,
					height: 600
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			let host = try #require(window.contentView)
			host.addSubview(item.view)
			defer
			{
				item.prepareForReuse()
				window.close()
			}
			let body = "![Current image](\(url.path))"
			var entries: [ConversationEntry] = []
			var previous: PreparedConversationContent?
			for (index, height) in [6, 10].enumerated()
			{
				if index > 0
				{
					try await BackgroundTestWork.perform
					{
						try writeImage(
							to: url,
							height: height,
							modifiedAt: 2_000
						)
					}
				}
				let content = await cache.content(
					body: body,
					markdown: true
				)
				#expect(content !== previous)
				#expect(content.hasLocalImageDependencies)
				#expect(content.estimatedRichImageBytes == 8 * height * 4)
				#expect(content.attributedString.attribute(
					.attachment,
					at: 0,
					effectiveRange: nil
				) is MarkdownImageGalleryAttachment)
				previous = content
				entries.append(ConversationEntry(
					id: "turn:reply\(index)",
					kind: .agent,
					title: "Codex",
					body: body
				))
				var published: [String: PreparedConversationContent] = [:]
				coordinator.prepare(
					entries,
					keys: entries.map
					{
						TranscriptPreparationCoordinator.ContentKey.make(
							for: $0,
							expanded: false
						)
					}
				)
				{
					published = $0
				}
				await coordinator.waitForRendering()
				#expect(published.count == entries.count)
				#expect(published.values
					.allSatisfy
					{
						$0.estimatedRichImageBytes == 8 * height * 4
					})
				let row = ConversationActivityRow(
					id: "image\(index)",
					sourceEntryID: "image\(index)",
					groupID: "image\(index)",
					kind: .image,
					title: "Viewed an image",
					imagePath: url.path,
					expanded: true
				)
				item.configure(
					row,
					onToggle:
					{
					},
					onOpenFile:
					{
						_ in
					}
				)
				await item.waitForImagePreview()
				let button = try #require(descendants(item.view).compactMap
				{
					$0 as? NSButton
				}
				.first
				{
					$0.accessibilityLabel() == "Open viewed image"
				})
				let inlineImage = try #require(button.image?.cgImage(
					forProposedRect: nil,
					context: nil,
					hints: nil
				))
				#expect(inlineImage.width == 8 && inlineImage.height == height)
				button.dispatchConfiguredAction()
				await item.waitForImagePreview()
				let expanded = try #require(descendants(host).compactMap
				{
					$0 as? NSImageView
				}
				.first
				{
					$0.accessibilityLabel()?.hasPrefix("Attached image:") == true
				})
				#expect(expanded.image?.size == NSSize(
					width: 8,
					height: CGFloat(height)
				))
			}
		}
	}

	@Test func activityThumbnailsRetainTheSharedInputByteLimit() async throws
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("transcript-oversized-\(UUID()).png")
		try await BackgroundTestWork.perform
		{
			try writeImage(
				to: url,
				height: 6,
				modifiedAt: 1_000
			)
			let handle = try FileHandle(forWritingTo: url)
			defer
			{
				try? handle.close()
			}
			try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
		}
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		let item = ConversationActivityCollectionItem()
		item.configure(
			ConversationActivityRow(
				id: "image",
				sourceEntryID: "image",
				groupID: "image",
				kind: .image,
				title: "Viewed an image",
				imagePath: url.path,
				expanded: true
			),
			onToggle:
			{
			},
			onOpenFile:
			{
				_ in
			}
		)
		await item.waitForImagePreview()
		#expect(descendants(item.view).compactMap
		{
			$0 as? NSTextField
		}
		.contains
		{
			$0.stringValue == "Image unavailable"
		})
		#expect(!descendants(item.view).compactMap
		{
			$0 as? NSButton
		}
		.contains
		{
			$0.accessibilityLabel() == "Open viewed image" && $0.image != nil
		})
	}

	@Test func inlineImageSourceRemainsEligibleForPreparedContentReuse() async throws
	{
		let bytes = try await BackgroundTestWork.perform
		{
			try pngData(height: 6)
		}
		let body = "![Inline](data:image/png;base64,\(bytes.base64EncodedString()))"
		let cache = ConversationContentCache()
		let first = await cache.content(
			body: body,
			markdown: true
		)
		let second = await cache.content(
			body: body,
			markdown: true
		)
		#expect(!first.hasLocalImageDependencies)
		#expect(first.estimatedRichImageBytes == 8 * 6 * 4)
		#expect(first === second)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}

private func writeImage(
	to url: URL,
	height: Int,
	modifiedAt: TimeInterval
) throws
{
	try pngData(height: height).write(to: url)
	try FileManager.default.setAttributes(
		[.modificationDate: Date(timeIntervalSince1970: modifiedAt)],
		ofItemAtPath: url.path
	)
}

private func pngData(height: Int) throws -> Data
{
	guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
		data: nil,
		width: 8,
		height: height,
		bitsPerComponent: 8,
		bytesPerRow: 32,
		space: colorSpace,
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	)
	else
	{
		throw CocoaError(.fileWriteUnknown)
	}
	context.setFillColor(CGColor(
		red: 0.2,
		green: 0.4,
		blue: 0.8,
		alpha: 1
	))
	context.fill(CGRect(
		x: 0,
		y: 0,
		width: 8,
		height: CGFloat(height)
	))
	guard let image = context.makeImage()
	else
	{
		throw CocoaError(.fileWriteUnknown)
	}
	let bytes = NSMutableData()
	guard let destination = CGImageDestinationCreateWithData(
		bytes,
		UTType.png.identifier as CFString,
		1,
		nil
	)
	else
	{
		throw CocoaError(.fileWriteUnknown)
	}
	CGImageDestinationAddImage(
		destination,
		image,
		nil
	)
	guard CGImageDestinationFinalize(destination)
	else
	{
		throw CocoaError(.fileWriteUnknown)
	}
	return bytes as Data
}
