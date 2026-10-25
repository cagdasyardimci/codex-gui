import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(
	.serialized
)
@MainActor
struct ComposerContextViewTests
{
	@Test func imageImportCreatesPreviewAndRemovalControl() async throws
	{
		_ = NSApplication.shared
		let directory = try await temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let bitmap = try #require(
			NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 2,
				pixelsHigh: 2,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 0,
				bitsPerPixel: 0
			)
		)
		bitmap.setColor(
			.systemRed,
			atX: 0,
			y: 0
		)
		let image = NSImage(size: NSSize(
			width: 2,
			height: 2
		))
		image.addRepresentation(bitmap)
		let item = try DraftImageStore(directory: directory).importImage(
			image,
			title: "Test screenshot"
		)
		#expect(item.kind == .image)
		#expect(item.path.map
		{
			FileManager.default.fileExists(atPath: $0)
		} == true)
		let view = ComposerContextView()
		var removedID: String?
		view.onRemove =
		{
			removedID = $0
		}
		view.render(items: [item])
		#expect(findImageView(in: view) != nil)
		let remove = try #require(findButton(
			in: view,
			title: "Remove"
		))
		#expect(findButton(
			in: view,
			title: "Inspect"
		) == nil)
		#expect(remove.alphaValue == 0)
		let tile = try #require(remove.superview as? ComposerImageAttachmentView)
		let event = try #require(NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		))
		tile.mouseEntered(with: event)
		#expect(remove.alphaValue == 1)
		tile.mouseExited(with: event)
		#expect(remove.alphaValue == 0)

		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 500,
				height: 240
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = view
		defer
		{
			window.close()
		}
		view.layoutSubtreeIfNeeded()
		#expect(abs(tile.frame.width - 120) < 0.5)
		#expect(abs(tile.frame.height - 120) < 0.5)
		let closeFrame = tile.convert(
			remove.bounds,
			from: remove
		)
		#expect(abs(tile.bounds.maxX - closeFrame.maxX - 4) < 0.5)
		#expect(abs(tile.bounds.maxY - closeFrame.maxY - 4) < 0.5)
		#expect(!containsTextField(in: view))
		let expand = try #require(findButton(
			in: tile,
			title: ""
		))
		expand.performClick(nil)
		await view.waitForExpandedPreview()
		let expanded = try #require(findExpandedPreview(in: view))
		#expect(findImageView(in: expanded)?.image != nil)
		#expect(window.attachedSheet == nil)
		view.render(items: [])
		#expect(expanded.superview == nil)
		remove.performClick(nil)
		#expect(removedID == nil)
		view.render(items: [item])
		let currentRemove = try #require(findButton(
			in: view,
			title: "Remove"
		))
		currentRemove.performClick(nil)
		#expect(removedID == item.id)
		let currentExpand = try #require(findButton(
			in: view,
			title: ""
		))
		currentExpand.performClick(nil)
		await view.waitForExpandedPreview()
		let reopened = try #require(findExpandedPreview(in: view))
		window.contentView = NSView()
		#expect(reopened.superview == nil)
	}

	private func findExpandedPreview(in view: NSView) -> NSView?
	{
		if view.accessibilityIdentifier() == "expanded-image-preview"
		{
			return view
		}
		return view.subviews.lazy.compactMap
		{
			findExpandedPreview(in: $0)
		}.first
	}

	private func imageTiles(in view: NSView) -> [ComposerImageAttachmentView]
	{
		if let tile = view as? ComposerImageAttachmentView
		{
			return [tile]
		}
		return view.subviews.flatMap
		{
			imageTiles(in: $0)
		}
	}

	private func containsTextField(in view: NSView) -> Bool
	{
		view is NSTextField || view.subviews.contains
		{
			containsTextField(in: $0)
		}
	}

	private func findImageView(in view: NSView) -> NSImageView?
	{
		if let imageView = view as? NSImageView
		{
			return imageView
		}
		return view.subviews.lazy.compactMap
		{
			findImageView(in: $0)
		}.first
	}

	private func findButton(
		in view: NSView,
		title: String
	) -> NSButton?
	{
		if let button = view as? NSButton, button.title == title
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			findButton(
				in: $0,
				title: title
			)
		}.first
	}

	nonisolated private func temporaryProject() async throws -> URL
	{
		try await BackgroundTestWork.perform
		{
			let url = FileManager.default.temporaryDirectory
				.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(
				at: url,
				withIntermediateDirectories: true
			)
			return url
		}
	}
}
