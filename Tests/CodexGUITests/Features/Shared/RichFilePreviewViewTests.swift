import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct RichFilePreviewViewTests
{
	@Test func providedMarkdownBytesRetainSelectionAndGeometryAcrossAppearance() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let preview = RichFilePreviewView(kind: .markdown)
			{
				Data("# Shared preview\n\n**Content**".utf8)
			}
			let window = attachedWindow(for: preview)
			defer
			{
				preview.cancelLoading()
				window.close()
			}
			await preview.waitForLoading()
			let text = try #require(preview.subviews.first as? MarkdownTextView)
			#expect(text.string.contains("Shared preview"))
			#expect(text.string.contains("Content"))
			#expect(!text.string.contains("**"))
			text.setSelectedRange(NSRange(
				location: 0,
				length: 6
			))
			for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: name)
				window.contentView?.layoutSubtreeIfNeeded()
				#expect(text.selectedRange() == NSRange(
					location: 0,
					length: 6
				))
				#expect(text.window === window)
				#expect(preview.frame.height > 0)
			}
		}
	}

	@Test func attachedMarkdownStartsFaviconsAfterLoadingAndAppearanceRefresh() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let imageSource = "![Diagram](missing.png)"
			let source = "A [site](https://localhost/guide)\n\n" + imageSource
			let preview = RichFilePreviewView(
				kind: .markdown,
				imageBaseDirectory: URL(
					fileURLWithPath: "/tmp/favicon-preview",
					isDirectory: true
				)
			)
			{
				Data(source.utf8)
			}
			let window = attachedWindow(for: preview)
			defer
			{
				preview.cancelLoading()
				window.close()
			}
			window.appearance = NSAppearance(named: .aqua)
			#expect(preview.window === window)
			#expect(preview.subviews.first is ViewerStatusView)
			await preview.waitForLoading()
			let text = try #require(preview.subviews.first as? MarkdownTextView)
			let storage = try #require(text.textStorage)
			let site = (text.string as NSString).range(of: "site")
			try #require(site.location != NSNotFound && site.location > 0)
			var favicon = try #require(storage.attribute(
				.attachment,
				at: site.location - 1,
				effectiveRange: nil
			) as? WebLinkFaviconAttachment)
			#expect(favicon.url.absoluteString == "https://localhost/guide")
			#expect(favicon.requested)
			#expect(text.accessibilityHelp() == imageSource)
			let displayed = text.string
			text.setSelectedRange(site)
			for name in [NSAppearance.Name.darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: name)
				window.contentView?.layoutSubtreeIfNeeded()
				let refreshed = try #require(storage.attribute(
					.attachment,
					at: site.location - 1,
					effectiveRange: nil
				) as? WebLinkFaviconAttachment)
				#expect(refreshed !== favicon)
				#expect(refreshed.requested)
				#expect(refreshed.url == favicon.url)
				#expect(text.selectedRange() == site)
				#expect(text.string == displayed)
				#expect(text.accessibilityValue() == displayed)
				#expect(text.accessibilityHelp() == imageSource)
				#expect(text.window === window)
				favicon = refreshed
			}
		}
	}

	@Test func invalidContentHasReadableMessageAndCancelledLoadCannotInstall() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let invalid = RichFilePreviewView(kind: .pdf)
			{
				Data("invalid PDF".utf8)
			}
			let window = attachedWindow(for: invalid)
			defer
			{
				invalid.cancelLoading()
				window.close()
			}
			await invalid.waitForLoading()
			let message = try #require((invalid.subviews.first as? ViewerStatusView)?.messageLabel)
			#expect(message.stringValue == "This PDF cannot be rendered as a rich preview.")
			let pending = RichFilePreviewView(kind: .markdown)
			{
				try? await Task.sleep(for: .milliseconds(100))
				return Data("# Obsolete".utf8)
			}
			pending.cancelLoading()
			await pending.waitForLoading()
			try await Task.sleep(for: .milliseconds(150))
			#expect(pending.subviews.compactMap
			{
				$0 as? ViewerStatusView
			}.first?.messageLabel.stringValue
			== "Loading preview…")
			#expect(!pending.subviews.contains
			{
				$0 is MarkdownTextView
			})
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

	@Test func providedImageAndPDFBytesRenderNativeViews() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let imageBytes = try pngBytes()
			let image = RichFilePreviewView(kind: .image)
			{
				imageBytes
			}
			defer
			{
				image.cancelLoading()
			}
			await image.waitForLoading()
			let imageView = try #require(image.subviews.first as? NSImageView)
			#expect(imageView.image?.size == NSSize(
				width: 16,
				height: 8
			))
			let document = PDFDocument()
			let sourceImage = try #require(NSImage(data: imageBytes))
			document.insert(
				try #require(PDFPage(image: sourceImage)),
				at: 0
			)
			let pdfBytes = try #require(document.dataRepresentation())
			let pdf = RichFilePreviewView(kind: .pdf)
			{
				pdfBytes
			}
			defer
			{
				pdf.cancelLoading()
			}
			await pdf.waitForLoading()
			let pdfView = try #require(pdf.subviews.first as? PDFView)
			#expect(pdfView.document?.pageCount == 1)
		}
	}

	@Test func SVGUsesBoundedNativeRasterAndMalformedSVGHasReadableFailure() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let valid = Data("""
			<svg xmlns="http://www.w3.org/2000/svg" width="8000" height="4000">
			<rect width="8000" height="4000" fill="red"/>
			</svg>
			""".utf8)
			let preview = RichFilePreviewView(kind: .image)
			{
				valid
			}
			defer
			{
				preview.cancelLoading()
			}
			await preview.waitForLoading()
			let image = try #require((preview.subviews.first as? NSImageView)?.image)
			#expect(image.size == NSSize(
				width: 8000,
				height: 4000
			))
			let pixels = try #require(image.cgImage(
				forProposedRect: nil,
				context: nil,
				hints: nil
			))
			#expect(pixels.width == 2048)
			#expect(pixels.height == 1024)
			let malformed = RichFilePreviewView(kind: .image)
			{
				Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect".utf8)
			}
			defer
			{
				malformed.cancelLoading()
			}
			await malformed.waitForLoading()
			let message = try #require((malformed.subviews.first as? ViewerStatusView)?
				.messageLabel)
			#expect(message.stringValue == "This image cannot be rendered as a rich preview.")
		}
	}

	@Test func localLinkDelegateUsesDocumentBaseAndLeavesExternalLinksToAppKit() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			var received: [URL] = []
			let source = "[Local](../guide.md) [Web](https://example.com)"
			let preview = RichFilePreviewView(
				kind: .markdown,
				imageBaseDirectory: URL(
					fileURLWithPath: "/tmp/workspace/docs",
					isDirectory: true
				),
				onOpenLink:
				{
					url in
					received.append(url)
					return url.isFileURL
				},
				loadContent:
				{
					Data(source.utf8)
				}
			)
			defer
			{
				preview.cancelLoading()
			}
			await preview.waitForLoading()
			let text = try #require(preview.subviews.first as? MarkdownTextView)
			let delegate = try #require(text.delegate as? RichFilePreviewView)
			let localIndex = (text.string as NSString).range(of: "Local").location
			let localLink = try #require(text.textStorage?.attribute(
				.link,
				at: localIndex,
				effectiveRange: nil
			))
			#expect(delegate.textView(
				text,
				clickedOnLink: localLink,
				at: localIndex
			))
			#expect(received.last?.path == "/tmp/workspace/guide.md")
			let webIndex = (text.string as NSString).range(of: "Web").location
			let webLink = try #require(text.textStorage?.attribute(
				.link,
				at: webIndex,
				effectiveRange: nil
			))
			#expect(!delegate.textView(
				text,
				clickedOnLink: webLink,
				at: webIndex
			))
			#expect(received.last?.absoluteString == "https://example.com")
			let defaultPreview = RichFilePreviewView(kind: .markdown)
			{
				Data(source.utf8)
			}
			defer
			{
				defaultPreview.cancelLoading()
			}
			await defaultPreview.waitForLoading()
			let defaultText = try #require(defaultPreview.subviews.first as? MarkdownTextView)
			#expect(defaultText.delegate == nil)
			#expect(defaultText.textStorage?.attribute(
				.link,
				at: webIndex,
				effectiveRange: nil
			) != nil)
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
		window.isReleasedWhenClosed = false
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
