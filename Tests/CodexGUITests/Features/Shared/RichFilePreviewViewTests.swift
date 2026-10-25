import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct RichFilePreviewViewTests
{

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

	private func pngBytes() throws -> Data
	{
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let context = try #require(CGContext(
			data: nil,
			width: 16,
			height: 8,
			bitsPerComponent: 8,
			bytesPerRow: 64,
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
			width: 16,
			height: 8
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
