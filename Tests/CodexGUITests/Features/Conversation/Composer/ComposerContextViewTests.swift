import AppKit
import Foundation
import Testing

@testable import CodexGUI

@Suite(.serialized)
@MainActor
struct ComposerContextViewTests
{
	@Test func imageImportCreatesPreviewAndRemovalControl() throws
	{
		_ = NSApplication.shared
		let directory = try temporaryProject()
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
		window.isReleasedWhenClosed = false
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
		let sheet = try #require(window.attachedSheet)
		#expect(findImageView(in: try #require(sheet.contentView)) != nil)
		window.endSheet(sheet)
		sheet.orderOut(nil)
		tile.mouseEntered(with: event)
		remove.performClick(nil)
		#expect(removedID == item.id)
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

	private func temporaryProject() throws -> URL
	{
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		return url
	}
}
