import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct UserMessageImageAttachmentsTests
{

	// Native event polling and transient panels share the application event/window state.
	@Test(
		.serialized,
		arguments: [false, true]
	)
	func localAndInlineImagesExpandInTheWindowAndReuseOrDetachDismissesThem(
		inline: Bool
	) async throws
	{
		_ = NSApplication.shared
		let imageData = try inlinePNG()
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("expanded-attachment-\(UUID()).png")
		defer
		{
			try? FileManager.default.removeItem(at: url)
		}
		try await BackgroundTestWork.perform
		{
			try imageData.write(to: url)
		}
		let path = inline
			? "data:image/png;base64," + imageData.base64EncodedString()
			: url.absoluteString
		let reference = try #require(UserMessageReference(
			json: ["type": inline ? "image" : "localImage", "url": path, "path": path],
			id: "attachment"
		))

		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin("native.body")
			defer
			{
				native.end()
			}
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
			parent.prepareForTesting()
			parent.contentView = strip
			defer
			{
				strip.configure([])
				parent.orderOut(nil)
			}
			strip.configure([reference])
			await strip.waitForImages()
			let button = try #require(strip.subviews.first as? NSButton)
			button.dispatchConfiguredAction()
			await strip.waitForExpandedPreview()
			let preview = try #require(descendants(strip).first
			{
				$0.accessibilityIdentifier() == "expanded-image-preview"
			})
			#expect(parent.attachedSheet == nil)
			#expect(parent.childWindows?.isEmpty != false)
			let imageView = try #require(descendants(preview).compactMap
			{
				$0 as? NSImageView
			}.first)
			#expect(imageView.image != nil)
			strip.configure([])
			#expect(parent.childWindows?.isEmpty != false)
			#expect(preview.superview == nil)
			#expect(button.target == nil && button.action == nil)

			strip.configure([reference])
			await strip.waitForImages()
			let current = try #require(strip.subviews.first as? NSButton)
			current.dispatchConfiguredAction()
			await strip.waitForExpandedPreview()
			let reopened = try #require(descendants(strip).first
			{
				$0.accessibilityIdentifier() == "expanded-image-preview"
			})
			parent.contentView = NSView()
			#expect(parent.childWindows?.isEmpty != false)
			#expect(reopened.superview == nil)
		}
	}

	private func inlinePNG(reverseColors: Bool = false) throws -> Data
	{
		let bytes = Data((0 ..< 8 * 6).flatMap
		{
			pixel -> [UInt8] in
			let red = (pixel % 8 < 4) != reverseColors
			return red ? [255, 0, 0, 255] : [0, 0, 255, 255]
		})
		let provider = try #require(CGDataProvider(data: bytes as CFData))
		let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
		let image = try #require(CGImage(
			width: 8,
			height: 6,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: 8 * 4,
			space: colorSpace,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		))
		return try #require(NSBitmapImageRep(cgImage: image).representation(
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
