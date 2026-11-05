import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct RichFilePreviewViewTests
{
	struct ImageLayoutCase: Sendable
	{
		let pixelSize: NSSize
		let expectedImageRect: NSRect
		let expectedCanvasHeight: CGFloat
	}

	@Test(arguments: [
		ImageLayoutCase(
			pixelSize: NSSize(
				width: 64,
				height: 64
			),
			expectedImageRect: NSRect(
				x: 168,
				y: 48,
				width: 64,
				height: 64
			),
			expectedCanvasHeight: 160
		),
		ImageLayoutCase(
			pixelSize: NSSize(
				width: 800,
				height: 400
			),
			expectedImageRect: NSRect(
				x: 12,
				y: 12,
				width: 376,
				height: 188
			),
			expectedCanvasHeight: 212
		),
		ImageLayoutCase(
			pixelSize: NSSize(
				width: 200,
				height: 1000
			),
			expectedImageRect: NSRect(
				x: 100,
				y: 12,
				width: 200,
				height: 1000
			),
			expectedCanvasHeight: 1024
		),
	])
	func imageDocumentsPreserveNaturalSizeAndFitFromTheViewportTop(
		_ sample: ImageLayoutCase
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			let bytes = try pngBytes(
				width: Int(sample.pixelSize.width),
				height: Int(sample.pixelSize.height)
			)
			let preview = RichFilePreviewView(
				kind: .image,
				loadContent:
				{
					bytes
				}
			)
			let scroll = NSScrollView(frame: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 300
			))
			scroll.borderType = .noBorder
			scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
			scroll.documentView = preview
			preview.translatesAutoresizingMaskIntoConstraints = false
			preview.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
			let window = attachedWindow(for: scroll)
			defer
			{
				preview.cancelLoading()
				window.close()
			}
			await preview.waitForLoading()
			window.contentView?.layoutSubtreeIfNeeded()
			scroll.layoutSubtreeIfNeeded()
			preview.layoutSubtreeIfNeeded()
			let image = try #require(preview.subviews.first as? NSImageView)
			let viewport = scroll.contentView
			let imageRect = viewport.convert(
				image.bounds,
				from: image
			)
			let topInset = viewport.isFlipped ? imageRect.minY - viewport.bounds.minY : viewport
				.bounds.maxY - imageRect.maxY
			#expect(abs(topInset - sample.expectedImageRect.minY) < 0.5)
			#expect(image.frame == sample.expectedImageRect)
			#expect(preview.frame.height == sample.expectedCanvasHeight)
			#expect(image.imageScaling == .scaleProportionallyDown)
		}
	}

	@Test func markdownImageLoaderReceivesResolvedPathAndDeniedImageKeepsSource() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let bytes = try pngBytes()
			let base = URL(
				fileURLWithPath: "/tmp/workspace/docs",
				isDirectory: true
			)
			let allowed = RichFilePreviewView(
				kind: .markdown,
				imageBaseDirectory: base,
				markdownImageLoader:
				{
					path, maximumPixelSize in
					guard path == "/tmp/workspace/docs/diagram.png"
					else
					{
						return nil
					}
					return await SourceThumbnailLoader.image(
						data: bytes,
						maximumPixelSize: maximumPixelSize
					)
				},
				loadContent:
				{
					Data("![Diagram](diagram.png)".utf8)
				}
			)
			defer
			{
				allowed.cancelLoading()
			}
			await allowed.waitForLoading()
			let allowedText = try #require(allowed.subviews.first as? MarkdownTextView)
			let gallery = allowedText.textStorage?.attribute(
				.attachment,
				at: 0,
				effectiveRange: nil
			) as? MarkdownImageGalleryAttachment
			#expect(gallery?.paths == ["/tmp/workspace/docs/diagram.png"])
			#expect(allowedText.textStorage?.attribute(
				.markdownSourceText,
				at: 0,
				effectiveRange: nil
			) as? String == "![Diagram](diagram.png)")
			let denied = RichFilePreviewView(
				kind: .markdown,
				imageBaseDirectory: base,
				markdownImageLoader:
				{
					path, _ in
					#expect(path == "/tmp/workspace/secrets.png")
					return nil
				},
				loadContent:
				{
					Data("![Secret](../secrets.png)".utf8)
				}
			)
			defer
			{
				denied.cancelLoading()
			}
			await denied.waitForLoading()
			let deniedText = try #require(denied.subviews.first as? MarkdownTextView)
			let fallback = deniedText.textStorage?.attribute(
				.attachment,
				at: 0,
				effectiveRange: nil
			) as? MarkdownRichAttachment
			#expect(fallback?.source == "![Secret](../secrets.png)")
		}
	}

	private func pngBytes(
		width: Int = 16,
		height: Int = 8
	) throws -> Data
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))
		context.setFillColor(CGColor(
			red: 0.3,
			green: 0.5,
			blue: 0.7,
			alpha: 1
		))
		context.fill(CGRect(
			x: 0,
			y: 0,
			width: width,
			height: height
		))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(
			data,
			UTType.png.identifier as CFString,
			1,
			nil
		))
		CGImageDestinationAddImage(
			destination,
			image,
			nil
		)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}

	private func attachedWindow(for preview: NSView) -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 400,
				height: 300
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let content = window.contentView!
		content.addSubview(preview)
		preview.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			preview.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			preview.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			preview.topAnchor.constraint(equalTo: content.topAnchor)
		])
		content.layoutSubtreeIfNeeded()
		return window
	}
}
